/**
 * SpecKitAgentsChart - Deploys SpecKit multi-agent workflow system
 *
 * This chart creates Kubernetes Deployments for each SpecKit agent:
 * - Orchestrator: Pure Dapr routing (no LLM)
 * - Specifier: Claude SDK agent - generates spec.md from feature descriptions
 * - Planner: Claude SDK agent with subagents - creates plan.md, research.md, data-model.md
 * - TaskGenerator: Claude SDK agent - produces dependency-ordered tasks.md
 * - Implementer: Claude SDK agent - executes tasks with TDD workflow
 *
 * Architecture:
 * - Claude Agent SDK handles all LLM-powered agent execution
 * - Dapr handles distributed systems (pub/sub, state store)
 * - Orchestrator is pure Dapr routing (no LLM calls)
 *
 * Agents communicate via Dapr pub/sub and are orchestrated through
 * the SpecKit workflow state machine.
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export interface SpecKitAgentConfig {
  /** Agent name (lowercase) */
  name: string;
  /** Dapr pub/sub topic for this agent */
  topic: string;
  /** Application port */
  port: number;
  /** Number of replicas */
  replicas?: number;
  /** Agent description for logging */
  description?: string;
}

export interface SpecKitAgentsChartProps extends ChartProps {
  /**
   * Namespace for agent deployments
   * @default 'dapr-agents'
   */
  namespace?: string;

  /**
   * Container image for agents
   * @default 'docker.io/vpittamp23/speckit-agents'
   */
  agentImage?: string;

  /**
   * Image tag
   * @default 'latest'
   */
  imageTag?: string;

  /**
   * Team name for agent registry
   * @default 'speckit'
   */
  teamName?: string;

  /**
   * Pub/Sub component name
   * @default 'messagepubsub'
   */
  pubsubName?: string;

  /**
   * Workflow state store name
   * @default 'workflowstatestore'
   */
  workflowStateStore?: string;

  /**
   * Agent registry state store name
   * @default 'agentregistrystore'
   */
  registryStateStore?: string;

  /**
   * Memory state store name
   * @default 'memorystore'
   */
  memoryStore?: string;

  /**
   * Secret name containing LLM API keys
   * Note: Claude SDK reads ANTHROPIC_API_KEY directly from environment
   * @default 'dapr-agents-llm-providers'
   */
  llmSecretName?: string;
}

export class SpecKitAgentsChart extends Chart {
  constructor(scope: Construct, id: string, props: SpecKitAgentsChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || 'dapr-agents';
    const agentImage = props.agentImage || 'docker.io/vpittamp23/speckit-agents';
    const imageTag = props.imageTag || 'latest';
    const teamName = props.teamName || 'speckit';
    const pubsubName = props.pubsubName || 'messagepubsub';
    const workflowStateStore = props.workflowStateStore || 'workflowstatestore';
    const registryStateStore = props.registryStateStore || 'agentregistrystore';
    const memoryStore = props.memoryStore || 'memorystore';
    const llmSecretName = props.llmSecretName || 'dapr-agents-llm-providers';

    // ArgoCD PreSync hook Job to wait for Dapr sidecar injector webhook to be ready
    // This prevents race condition where pods are created before webhook CA is propagated
    new k8s.KubeJob(this, 'wait-for-dapr-injector', {
      metadata: {
        name: 'speckit-wait-for-dapr-injector',
        namespace: namespace,
        annotations: {
          'argocd.argoproj.io/hook': 'PreSync',
          'argocd.argoproj.io/hook-delete-policy': 'BeforeHookCreation,HookSucceeded',
        },
        labels: {
          'app.kubernetes.io/name': 'speckit-wait-for-dapr-injector',
          'app.kubernetes.io/component': 'presync-hook',
          'app.kubernetes.io/part-of': 'speckit',
        },
      },
      spec: {
        ttlSecondsAfterFinished: 60,
        backoffLimit: 10,
        template: {
          metadata: {
            labels: {
              'app.kubernetes.io/name': 'speckit-wait-for-dapr-injector',
            },
          },
          spec: {
            restartPolicy: 'OnFailure',
            serviceAccountName: 'speckit-agents',
            containers: [
              {
                name: 'wait-for-dapr',
                image: 'bitnami/kubectl:latest',
                command: ['sh', '-c'],
                args: [
                  `echo "Waiting for Dapr sidecar injector webhook to be ready..." && \
                   for i in $(seq 1 60); do \
                     CA=$(kubectl get mutatingwebhookconfiguration dapr-sidecar-injector -o jsonpath='{.webhooks[0].clientConfig.caBundle}' 2>/dev/null); \
                     if [ -n "$CA" ] && echo "$CA" | grep -q '^[A-Za-z0-9]'; then \
                       echo "Dapr sidecar injector is ready with CA bundle!"; \
                       sleep 5; \
                       exit 0; \
                     fi; \
                     echo "Attempt $i: Dapr sidecar injector not ready, waiting..."; \
                     sleep 2; \
                   done && \
                   echo "Timeout waiting for Dapr sidecar injector" && exit 1`
                ],
              },
            ],
          },
        },
      },
    });

    // Define all SpecKit agents
    const agents: SpecKitAgentConfig[] = [
      {
        name: 'orchestrator',
        topic: `${teamName}.orchestrator.requests`,
        port: 8000,
        replicas: 1,
        description: 'Pure Dapr routing - no LLM, manages workflow lifecycle',
      },
      {
        name: 'specifier',
        topic: `${teamName}.specifier.requests`,
        port: 8001,
        replicas: 1,
        description: 'Claude SDK agent - generates spec.md from feature descriptions',
      },
      {
        name: 'planner',
        topic: `${teamName}.planner.requests`,
        port: 8002,
        replicas: 1,
        description: 'Claude SDK agent with parallel subagents - creates plan.md, research.md, data-model.md',
      },
      {
        name: 'task-generator',
        topic: `${teamName}.task-generator.requests`,
        port: 8003,
        replicas: 1,
        description: 'Claude SDK agent - produces dependency-ordered tasks.md',
      },
      {
        name: 'implementer',
        topic: `${teamName}.implementer.requests`,
        port: 8004,
        replicas: 1,
        description: 'Claude SDK agent - executes tasks with TDD workflow',
      },
    ];

    // Create deployment and service for each agent
    agents.forEach(agent => {
      this.createAgentDeployment(
        agent,
        namespace,
        agentImage,
        imageTag,
        teamName,
        pubsubName,
        workflowStateStore,
        registryStateStore,
        memoryStore,
        llmSecretName
      );
    });
  }

  private createAgentDeployment(
    agent: SpecKitAgentConfig,
    namespace: string,
    image: string,
    tag: string,
    teamName: string,
    pubsubName: string,
    workflowStateStore: string,
    registryStateStore: string,
    memoryStore: string,
    llmSecretName: string
  ): void {
    const appId = `speckit-${agent.name}`;

    const labels = {
      app: appId,
      'app.kubernetes.io/name': appId,
      'app.kubernetes.io/component': 'agent',
      'app.kubernetes.io/part-of': 'speckit',
      'speckit.io/agent-type': agent.name,
    };

    // Dapr sidecar annotations
    const daprAnnotations = {
      // Enable Dapr sidecar injection
      'dapr.io/enabled': 'true',
      // Application ID for service discovery
      'dapr.io/app-id': appId,
      // Application port for Dapr to forward requests
      'dapr.io/app-port': String(agent.port),
      // Enable API logging for debugging
      'dapr.io/enable-api-logging': 'true',
      // Log level
      'dapr.io/log-level': 'info',
      // Enable metrics
      'dapr.io/enable-metrics': 'true',
      // App protocol (http or grpc)
      'dapr.io/app-protocol': 'http',
      // Configure sidecar to wait for app
      'dapr.io/sidecar-listen-addresses': '0.0.0.0',
      // Tracing configuration - send traces to Jaeger via Zipkin
      'dapr.io/config': 'speckit-tracing',
    };

    // Environment variables for the agent
    const envVars: k8s.EnvVar[] = [
      // Agent identity
      { name: 'AGENT_NAME', value: agent.name },
      { name: 'AGENT_TOPIC', value: agent.topic },
      { name: 'AGENT_APP_ID', value: appId },
      { name: 'AGENT_PORT', value: String(agent.port) },

      // Team configuration
      { name: 'TEAM_NAME', value: teamName },
      { name: 'BROADCAST_TOPIC', value: `${teamName}.broadcast` },
      { name: 'WORKFLOW_STATUS_TOPIC', value: `${teamName}.workflow.status` },

      // Dapr component names
      { name: 'PUBSUB_NAME', value: pubsubName },
      { name: 'WORKFLOW_STATE_STORE', value: workflowStateStore },
      { name: 'REGISTRY_STATE_STORE', value: registryStateStore },
      { name: 'MEMORY_STORE', value: memoryStore },
      // Note: CONVERSATION_COMPONENT removed - Claude SDK reads ANTHROPIC_API_KEY directly

      // Dapr sidecar address (injected automatically)
      { name: 'DAPR_HTTP_PORT', value: '3500' },
      { name: 'DAPR_GRPC_PORT', value: '50001' },

      // Langfuse observability configuration
      // LangfuseOpenAIChatClient uses direct HTTP ingestion API to log LLM calls
      { name: 'LANGFUSE_HOST', value: 'http://langfuse.observability.svc.cluster.local:3000' },
      { name: 'LANGFUSE_ENABLED', value: 'true' },
      // Project-specific API keys from langfuse-init secret (generated during headless initialization)
      { name: 'LANGFUSE_PUBLIC_KEY', value: 'pk-lf-37df8de0-fbee-4c38-a0cc-05ce1ceb22c0' },
      { name: 'LANGFUSE_SECRET_KEY', value: 'sk-lf-76f23bdc-7782-4064-8ffd-c163c203a5b7' },
    ];

    // Deployment
    new k8s.KubeDeployment(this, `${agent.name}-deployment`, {
      metadata: {
        name: appId,
        namespace: namespace,
        labels: labels,
        annotations: {
          'speckit.io/description': agent.description || '',
        },
      },
      spec: {
        replicas: agent.replicas || 1,
        selector: {
          matchLabels: {
            app: appId,
          },
        },
        template: {
          metadata: {
            labels: labels,
            annotations: daprAnnotations,
          },
          spec: {
            serviceAccountName: 'speckit-agents',
            containers: [
              {
                name: agent.name,
                image: `${image}:${tag}`,
                imagePullPolicy: 'IfNotPresent',
                ports: [
                  { containerPort: agent.port, name: 'http' },
                ],
                env: envVars,
                // Mount LLM API keys as environment variables
                envFrom: [
                  {
                    secretRef: {
                      name: llmSecretName,
                      optional: true,
                    },
                  },
                ],
                resources: {
                  requests: {
                    cpu: k8s.Quantity.fromString('100m'),
                    memory: k8s.Quantity.fromString('512Mi'),
                  },
                  limits: {
                    cpu: k8s.Quantity.fromString('1000m'),
                    memory: k8s.Quantity.fromString('1536Mi'),
                  },
                },
                livenessProbe: {
                  httpGet: {
                    path: '/healthz',
                    port: k8s.IntOrString.fromNumber(agent.port),
                  },
                  initialDelaySeconds: 30,
                  periodSeconds: 10,
                  timeoutSeconds: 5,
                  failureThreshold: 3,
                },
                readinessProbe: {
                  httpGet: {
                    path: '/ready',
                    port: k8s.IntOrString.fromNumber(agent.port),
                  },
                  initialDelaySeconds: 5,
                  periodSeconds: 5,
                  timeoutSeconds: 3,
                  successThreshold: 1,
                  failureThreshold: 3,
                },
              },
            ],
          },
        },
      },
    });

    // Service
    new k8s.KubeService(this, `${agent.name}-service`, {
      metadata: {
        name: appId,
        namespace: namespace,
        labels: labels,
      },
      spec: {
        selector: {
          app: appId,
        },
        ports: [
          {
            port: agent.port,
            targetPort: k8s.IntOrString.fromNumber(agent.port),
            name: 'http',
          },
        ],
      },
    });
  }
}

/**
 * SpecKitAgentsRbacChart - RBAC resources for SpecKit Agents
 *
 * Creates ServiceAccount, Role, and RoleBinding for agents.
 * Separate chart to allow independent sync wave.
 */
export class SpecKitAgentsRbacChart extends Chart {
  constructor(scope: Construct, id: string, props: ChartProps & { namespace?: string } = {}) {
    super(scope, id, props);

    const namespace = props.namespace || 'dapr-agents';

    // ServiceAccount for agents
    new k8s.KubeServiceAccount(this, 'speckit-agents-sa', {
      metadata: {
        name: 'speckit-agents',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'speckit-agents',
          'app.kubernetes.io/component': 'rbac',
          'app.kubernetes.io/part-of': 'speckit',
        },
      },
    });

    // Role for Dapr component access
    new k8s.KubeRole(this, 'speckit-agents-role', {
      metadata: {
        name: 'speckit-agents',
        namespace: namespace,
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['secrets'],
          verbs: ['get', 'list'],
          resourceNames: ['dapr-agents-llm-providers'],
        },
        {
          apiGroups: ['dapr.io'],
          resources: ['components'],
          verbs: ['get', 'list', 'watch'],
        },
      ],
    });

    // RoleBinding
    new k8s.KubeRoleBinding(this, 'speckit-agents-rolebinding', {
      metadata: {
        name: 'speckit-agents',
        namespace: namespace,
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: 'speckit-agents',
          namespace: namespace,
        },
      ],
      roleRef: {
        kind: 'Role',
        name: 'speckit-agents',
        apiGroup: 'rbac.authorization.k8s.io',
      },
    });

    // ClusterRole for reading MutatingWebhookConfigurations (cluster-scoped)
    // Required for PreSync hook to check if Dapr sidecar injector is ready
    new k8s.KubeClusterRole(this, 'speckit-webhook-reader', {
      metadata: {
        name: 'speckit-webhook-reader',
        labels: {
          'app.kubernetes.io/name': 'speckit-agents',
          'app.kubernetes.io/component': 'rbac',
          'app.kubernetes.io/part-of': 'speckit',
        },
      },
      rules: [
        {
          apiGroups: ['admissionregistration.k8s.io'],
          resources: ['mutatingwebhookconfigurations'],
          verbs: ['get', 'list'],
          resourceNames: ['dapr-sidecar-injector'],
        },
      ],
    });

    // ClusterRoleBinding
    new k8s.KubeClusterRoleBinding(this, 'speckit-webhook-reader-binding', {
      metadata: {
        name: 'speckit-webhook-reader',
        labels: {
          'app.kubernetes.io/name': 'speckit-agents',
          'app.kubernetes.io/component': 'rbac',
          'app.kubernetes.io/part-of': 'speckit',
        },
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: 'speckit-agents',
          namespace: namespace,
        },
      ],
      roleRef: {
        kind: 'ClusterRole',
        name: 'speckit-webhook-reader',
        apiGroup: 'rbac.authorization.k8s.io',
      },
    });
  }
}
