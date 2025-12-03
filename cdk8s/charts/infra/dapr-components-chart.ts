/**
 * DaprComponentsChart - Deploys Dapr components for SpecKit Agents
 *
 * This chart creates the Dapr components needed by SpecKit agents:
 * - State stores: workflowstatestore (with actor support), agentregistrystore, memorystore
 * - Pub/Sub: messagepubsub for agent communication
 * - Conversation: anthropic for Claude Opus 4.5 LLM integration
 *
 * All components use Redis as the backend, deployed by DaprAgentsRedisChart.
 */

import { Chart, ChartProps, ApiObject } from 'cdk8s';
import { Construct } from 'constructs';

export interface DaprComponentsChartProps extends ChartProps {
  /**
   * Namespace for Dapr components
   * @default 'dapr-agents'
   */
  namespace?: string;

  /**
   * Redis host address
   * @default 'redis-service.dapr-agents.svc.cluster.local:6379'
   */
  redisHost?: string;

  /**
   * Secret name containing LLM API keys
   * @default 'dapr-agents-llm-providers'
   */
  llmSecretName?: string;

  /**
   * Anthropic model to use
   * @default 'claude-opus-4-5-20251101'
   */
  anthropicModel?: string;

  /**
   * Prompt cache TTL (Go duration format)
   * @default '10m'
   */
  cacheTTL?: string;
}

export class DaprComponentsChart extends Chart {
  constructor(scope: Construct, id: string, props: DaprComponentsChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || 'dapr-agents';
    const redisHost = props.redisHost || 'redis-service.dapr-agents.svc.cluster.local:6379';
    const llmSecretName = props.llmSecretName || 'dapr-agents-llm-providers';
    const anthropicModel = props.anthropicModel || 'claude-opus-4-5-20251101';
    const cacheTTL = props.cacheTTL || '10m';

    // =========================================================================
    // State Stores
    // =========================================================================

    // State Store: workflowstatestore (with actor support for Dapr Workflows)
    new ApiObject(this, 'workflowstatestore', {
      apiVersion: 'dapr.io/v1alpha1',
      kind: 'Component',
      metadata: {
        name: 'workflowstatestore',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'workflowstatestore',
          'app.kubernetes.io/component': 'state-store',
          'app.kubernetes.io/part-of': 'dapr-agents',
        },
      },
      spec: {
        type: 'state.redis',
        version: 'v1',
        metadata: [
          { name: 'redisHost', value: redisHost },
          { name: 'redisPassword', value: '' },
          { name: 'actorStateStore', value: 'true' }, // Required for Dapr Workflows
          { name: 'keyPrefix', value: 'workflow' },
        ],
      },
    });

    // State Store: agentregistrystore (for agent discovery)
    new ApiObject(this, 'agentregistrystore', {
      apiVersion: 'dapr.io/v1alpha1',
      kind: 'Component',
      metadata: {
        name: 'agentregistrystore',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'agentregistrystore',
          'app.kubernetes.io/component': 'state-store',
          'app.kubernetes.io/part-of': 'dapr-agents',
        },
      },
      spec: {
        type: 'state.redis',
        version: 'v1',
        metadata: [
          { name: 'redisHost', value: redisHost },
          { name: 'redisPassword', value: '' },
          { name: 'keyPrefix', value: 'none' }, // Allow direct key access for registry
        ],
      },
    });

    // State Store: memorystore (for conversation memory)
    new ApiObject(this, 'memorystore', {
      apiVersion: 'dapr.io/v1alpha1',
      kind: 'Component',
      metadata: {
        name: 'memorystore',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'memorystore',
          'app.kubernetes.io/component': 'state-store',
          'app.kubernetes.io/part-of': 'dapr-agents',
        },
      },
      spec: {
        type: 'state.redis',
        version: 'v1',
        metadata: [
          { name: 'redisHost', value: redisHost },
          { name: 'redisPassword', value: '' },
          { name: 'keyPrefix', value: 'memory' },
        ],
      },
    });

    // =========================================================================
    // Pub/Sub
    // =========================================================================

    // Pub/Sub: messagepubsub (for agent communication)
    new ApiObject(this, 'messagepubsub', {
      apiVersion: 'dapr.io/v1alpha1',
      kind: 'Component',
      metadata: {
        name: 'messagepubsub',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'messagepubsub',
          'app.kubernetes.io/component': 'pubsub',
          'app.kubernetes.io/part-of': 'dapr-agents',
        },
      },
      spec: {
        type: 'pubsub.redis',
        version: 'v1',
        metadata: [
          { name: 'redisHost', value: redisHost },
          { name: 'redisPassword', value: '' },
          { name: 'consumerID', value: 'speckit-agents' },
        ],
      },
    });

    // =========================================================================
    // Conversation (LLM)
    // =========================================================================

    // Conversation: anthropic (Claude Opus 4.5)
    new ApiObject(this, 'anthropic', {
      apiVersion: 'dapr.io/v1alpha1',
      kind: 'Component',
      metadata: {
        name: 'anthropic',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'anthropic',
          'app.kubernetes.io/component': 'conversation',
          'app.kubernetes.io/part-of': 'dapr-agents',
        },
      },
      spec: {
        type: 'conversation.anthropic',
        version: 'v1',
        metadata: [
          {
            name: 'key',
            secretKeyRef: {
              name: llmSecretName,
              key: 'ANTHROPIC_API_KEY',
            },
          },
          { name: 'model', value: anthropicModel },
          { name: 'cacheTTL', value: cacheTTL },
        ],
      },
    });

    // Optional: OpenAI as fallback/alternative
    new ApiObject(this, 'openai', {
      apiVersion: 'dapr.io/v1alpha1',
      kind: 'Component',
      metadata: {
        name: 'openai',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'openai',
          'app.kubernetes.io/component': 'conversation',
          'app.kubernetes.io/part-of': 'dapr-agents',
        },
      },
      spec: {
        type: 'conversation.openai',
        version: 'v1',
        metadata: [
          {
            name: 'key',
            secretKeyRef: {
              name: llmSecretName,
              key: 'OPENAI_API_KEY',
            },
          },
          { name: 'model', value: 'gpt-4o' },
        ],
      },
    });
  }
}
