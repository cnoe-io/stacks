/**
 * SpecKitAgentsChart - Deploys SpecKit multi-agent workflow system
 *
 * This chart creates Kubernetes Deployments for each SpecKit agent:
 * - Orchestrator: LLM-based routing to appropriate agent
 * - Specifier: Generates spec.md from feature descriptions
 * - Planner: Creates plan.md, research.md, data-model.md
 * - TaskGenerator: Produces dependency-ordered tasks.md
 * - Implementer: Executes tasks phase-by-phase
 *
 * Each deployment is annotated for Dapr sidecar injection with:
 * - Pub/Sub subscription for agent topic
 * - State store access
 * - Conversation component for LLM
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
   * @default 'ghcr.io/pittampalliorg/speckit-agents'
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
   * Conversation component name (LLM)
   * @default 'anthropic'
   */
  conversationComponent?: string;

  /**
   * Secret name containing LLM API keys
   * @default 'dapr-agents-llm-providers'
   */
  llmSecretName?: string;
}

export class SpecKitAgentsChart extends Chart {
  constructor(scope: Construct, id: string, props: SpecKitAgentsChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || 'dapr-agents';
    const agentImage = props.agentImage || 'speckit-agents';
    const imageTag = props.imageTag || 'latest';
    const teamName = props.teamName || 'speckit';
    const pubsubName = props.pubsubName || 'messagepubsub';
    const workflowStateStore = props.workflowStateStore || 'workflowstatestore';
    const registryStateStore = props.registryStateStore || 'agentregistrystore';
    const memoryStore = props.memoryStore || 'memorystore';
    const conversationComponent = props.conversationComponent || 'anthropic';
    const llmSecretName = props.llmSecretName || 'dapr-agents-llm-providers';

    // Define all SpecKit agents
    const agents: SpecKitAgentConfig[] = [
      {
        name: 'orchestrator',
        topic: `${teamName}.orchestrator.requests`,
        port: 8000,
        replicas: 1,
        description: 'LLM-based routing to appropriate agent based on workflow phase',
      },
      {
        name: 'specifier',
        topic: `${teamName}.specifier.requests`,
        port: 8001,
        replicas: 1,
        description: 'Generates spec.md from feature descriptions',
      },
      {
        name: 'planner',
        topic: `${teamName}.planner.requests`,
        port: 8002,
        replicas: 1,
        description: 'Creates plan.md, research.md, data-model.md, contracts/',
      },
      {
        name: 'task-generator',
        topic: `${teamName}.task-generator.requests`,
        port: 8003,
        replicas: 1,
        description: 'Produces dependency-ordered tasks.md',
      },
      {
        name: 'implementer',
        topic: `${teamName}.implementer.requests`,
        port: 8004,
        replicas: 1,
        description: 'Executes tasks phase-by-phase with TDD approach',
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
        conversationComponent,
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
    conversationComponent: string,
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
      { name: 'CONVERSATION_COMPONENT', value: conversationComponent },

      // Dapr sidecar address (injected automatically)
      { name: 'DAPR_HTTP_PORT', value: '3500' },
      { name: 'DAPR_GRPC_PORT', value: '50001' },
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
                    memory: k8s.Quantity.fromString('256Mi'),
                  },
                  limits: {
                    cpu: k8s.Quantity.fromString('500m'),
                    memory: k8s.Quantity.fromString('512Mi'),
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
  }
}
