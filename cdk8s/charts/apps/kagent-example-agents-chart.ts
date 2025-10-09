/**
 * KagentExampleAgentsChart - Example AI agents and MCP servers
 *
 * This chart creates example agents demonstrating kagent capabilities:
 * 1. k8s-agent - Kubernetes resource query agent
 * 2. fetch-agent - Web content fetcher agent with custom MCP server
 * 3. a2a-agent - Agent with A2A protocol enabled for external integrations
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { createModelConfig, createAgent, createA2ASkill, createA2AConfig, kagentSyncWave } from '../../lib/kagent-helpers';
import { createFastMCPServer } from '../../lib/mcp-tool-builders';

export class KagentExampleAgentsChart extends Chart {
  constructor(scope: Construct, id: string, props?: ChartProps) {
    super(scope, id, props);

    const ns = 'kagent';

    // Default ModelConfig (OpenAI)
    createModelConfig(
      this,
      'default-model-config',
      ns,
      'openAI',
      'kagent-llm-providers',
      'OPENAI_API_KEY',
      'gpt-4-turbo-preview'
    );

    // Example 1: k8s-agent - Kubernetes resource query agent
    createAgent(
      this,
      'k8s-agent',
      ns,
      'Agent for querying Kubernetes cluster resources',
      `You are an expert Kubernetes agent with deep knowledge of cluster operations.
Use the available K8s tools to help users query and understand their cluster resources.

Guidelines:
- Always use k8s_get_available_api_resources first to discover resource types
- Use k8s_get_resources to retrieve specific resource details
- Explain resource relationships and dependencies clearly
- Highlight any potential issues or misconfigurations`,
      [
        {
          type: 'McpServer',
          mcpServer: {
            name: 'kagent-tool-server',
            kind: 'RemoteMCPServer',
            toolNames: ['k8s_get_resources', 'k8s_get_available_api_resources'],
          },
        },
      ],
      'default-model-config'
    );

    // Example 2: MCP Website Fetcher Server
    createFastMCPServer(
      this,
      'mcp-website-fetcher',
      ns,
      'mcp-server-fetch'
    );

    // Example 2: fetch-agent - Web content fetcher agent
    createAgent(
      this,
      'fetch-agent',
      ns,
      'Agent that fetches and summarizes web content',
      `You are a web content research assistant.
When users ask about websites or online resources:
1. Use the fetch tool to retrieve web content
2. Analyze and summarize the key information
3. Provide concise, accurate answers based on the content

Be helpful, accurate, and cite sources when appropriate.`,
      [
        {
          type: 'McpServer',
          mcpServer: {
            name: 'mcp-website-fetcher',
            kind: 'MCPServer',
            toolNames: ['fetch'],
          },
        },
      ],
      'default-model-config'
    );

    // Example 3: a2a-agent - Agent with A2A protocol enabled
    const getResourcesSkill = createA2ASkill(
      'get-resources-skill',
      'Get Kubernetes Resources',
      'Query and retrieve information about Kubernetes cluster resources',
      ['k8s', 'resources', 'query']
    );

    const a2aConfig = createA2AConfig([getResourcesSkill]);

    createAgent(
      this,
      'a2a-agent',
      ns,
      'Agent with A2A protocol enabled for external integrations',
      `You are a Kubernetes operations agent accessible via the A2A protocol.
Help external systems and other agents query cluster resources effectively.
Provide clear, structured responses suitable for programmatic consumption.`,
      [
        {
          type: 'McpServer',
          mcpServer: {
            name: 'kagent-tool-server',
            kind: 'RemoteMCPServer',
            toolNames: ['k8s_get_resources', 'k8s_get_available_api_resources'],
          },
        },
      ],
      'default-model-config',
      a2aConfig
    );
  }
}
