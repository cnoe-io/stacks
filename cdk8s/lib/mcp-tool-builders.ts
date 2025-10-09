/**
 * Helper functions for creating MCP (Model Context Protocol) Server resources
 * Provides reusable builders for common MCP server patterns
 */

import { McpServer, McpServerSpec, McpServerSpecTransportType } from '../imports/kagent.dev';
import { Construct } from 'constructs';

/**
 * Creates an MCPServer resource
 *
 * @param scope - CDK8s construct scope
 * @param name - MCPServer name
 * @param namespace - Kubernetes namespace
 * @param cmd - Command to run (e.g., 'uvx', 'python', 'node')
 * @param args - Command arguments (e.g., ['mcp-server-fetch'])
 * @param port - Optional port for HTTP transport (default: 3000)
 * @param env - Optional environment variables
 * @param image - Optional container image (if not using cmd/args pattern)
 * @returns MCPServer resource
 */
export function createMCPServer(
  scope: Construct,
  name: string,
  namespace: string,
  cmd: string,
  args: string[],
  port?: number,
  env?: Record<string, string>,
  image?: string
): McpServer {
  const spec: McpServerSpec = {
    deployment: {
      cmd,
      args,
      ...(port ? { port } : {}),
      ...(env ? { env } : {}),
      ...(image ? { image } : {}),
    },
    transportType: McpServerSpecTransportType.STDIO, // Default to stdio transport
    stdioTransport: {},
  };

  return new McpServer(scope, `mcpserver-${name}`, {
    metadata: {
      name,
      namespace,
      labels: {
        'app.kubernetes.io/name': name,
        'app.kubernetes.io/component': 'mcp-server',
      },
    },
    spec,
  });
}

/**
 * Creates a FastMCP-based MCPServer using uvx to run Python MCP servers
 * This is a convenience wrapper for the common pattern of running FastMCP servers
 *
 * @param scope - CDK8s construct scope
 * @param name - MCPServer name
 * @param namespace - Kubernetes namespace
 * @param packageName - FastMCP package name (e.g., 'mcp-server-fetch')
 * @param env - Optional environment variables
 * @returns MCPServer resource
 */
export function createFastMCPServer(
  scope: Construct,
  name: string,
  namespace: string,
  packageName: string,
  env?: Record<string, string>,
  image?: string
): McpServer {
  return createMCPServer(
    scope,
    name,
    namespace,
    'uvx',
    [packageName],
    3000,
    env,
    image || 'python:3.12-slim' // Default Python image with pip/uvx support
  );
}
