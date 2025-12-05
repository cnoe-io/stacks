/**
 * Tailscale Serve Helpers
 *
 * Shared helper functions for Tailscale serve chart implementations.
 * Used to generate the shell script that runs in the tailscale serve container.
 */

import { ResolvedTailscaleServeChartProps } from './tailscale-serve-chart-props';

/**
 * Generate the shell script for the Tailscale serve container.
 *
 * This script:
 * 1. Starts tailscaled in userspace mode (no TUN device needed)
 * 2. Installs socat for local TCP proxy
 * 3. Sets up socat to proxy backend service to localhost
 * 4. Waits for tailscaled to be ready
 * 5. Brings up the Tailscale node with authentication
 * 6. Starts tailscale serve with either:
 *    - Tailscale Services mode (--service flag) for stable URLs
 *    - Legacy hostname mode for backward compatibility
 *
 * @param props Resolved chart properties with defaults applied
 * @returns Shell script string for container args
 */
export function generateTailscaleServeScript(props: ResolvedTailscaleServeChartProps): string {
  const {
    serviceName,
    backendHost,
    backendPort,
    exposedPort,
    backendScheme,
    legacyHostnameMode,
    legacyHostname,
  } = props;

  // Determine local proxy port for socat
  // For TLS passthrough backends (https+insecure://), socat must listen on 443
  // because tailscale serve just proxies without TLS termination
  // For HTTP backends (http://), socat must listen on a different port (e.g., 8080)
  // so tailscale serve can handle TLS termination on 443
  const localPort = backendScheme.startsWith('https') ? exposedPort : 8080;

  // Build the tailscale serve command based on mode
  let serveCommand: string;
  let logMessage: string;

  if (legacyHostnameMode && legacyHostname) {
    // Legacy mode: use device hostname
    serveCommand = `tailscale --socket=/run/tailscale/tailscaled.sock \\
  serve --bg ${backendScheme}://127.0.0.1:\${PORT_FWD}`;
    logMessage = `echo "tailscale serve running at $TS_HOSTNAME (legacy hostname mode)"`;
  } else {
    // Tailscale Services mode: use --service flag
    // Note: --service automatically runs in background mode
    serveCommand = `tailscale --socket=/run/tailscale/tailscaled.sock \\
  serve --service=svc:${serviceName} --https=${exposedPort} ${backendScheme}://127.0.0.1:\${PORT_FWD}`;
    logMessage = `echo "tailscale serve running for ${serviceName} service (svc:${serviceName})"`;
  }

  // Build the hostname env var assignment
  const hostnameEnv = legacyHostnameMode && legacyHostname
    ? `--hostname="$TS_HOSTNAME" \\`
    : '';

  return `
set -euo pipefail

# start tailscaled in userspace mode (no TUN device needed)
mkdir -p /var/lib/tailscale
tailscaled --tun=userspace-networking \\
  --socket=/run/tailscale/tailscaled.sock \\
  --state=/var/lib/tailscale/tailscaled.state &

# install lightweight TCP proxy to keep backend on localhost (required by tailscale serve)
apk add --no-cache socat >/dev/null
PORT_FWD=${localPort}
socat TCP-LISTEN:\${PORT_FWD},fork,reuseaddr TCP:${backendHost}:${backendPort} &

# wait for tailscaled to come up
for i in $(seq 1 40); do
  tailscale --socket=/run/tailscale/tailscaled.sock status >/dev/null 2>&1 && break
  sleep 0.5
done

# bring the node up (no DNS/routes/ssh)
tailscale --socket=/run/tailscale/tailscaled.sock up \\
  --authkey="$TS_AUTHKEY" \\
  ${hostnameEnv}--accept-dns=false --accept-routes=false --ssh=false

# wait for node registration and tag assignment before advertising service
# This ensures the node's tag is registered with control server for auto-approval
sleep 5

# expose service via tailscale serve
${serveCommand}

${logMessage}
exec tail -f /dev/null
`;
}

/**
 * Generate environment variables for the Tailscale serve container.
 *
 * @param props Resolved chart properties
 * @returns Array of environment variable definitions
 */
export function generateTailscaleEnvVars(props: ResolvedTailscaleServeChartProps): Array<{
  name: string;
  value?: string;
  valueFrom?: {
    secretKeyRef: { name: string; key: string };
  };
}> {
  const envVars: Array<{
    name: string;
    value?: string;
    valueFrom?: {
      secretKeyRef: { name: string; key: string };
    };
  }> = [
    {
      name: 'TS_AUTHKEY',
      valueFrom: {
        secretKeyRef: {
          name: props.authKeySecretName,
          key: props.authKeySecretKey,
        },
      },
    },
  ];

  // Only add TS_HOSTNAME in legacy mode
  if (props.legacyHostnameMode && props.legacyHostname) {
    envVars.push({
      name: 'TS_HOSTNAME',
      value: props.legacyHostname,
    });
  }

  return envVars;
}
