import { Construct } from 'constructs';
import * as k8s from '../imports/k8s';

/**
 * Properties for DevSpaceSSHConstruct
 */
export interface DevSpaceSSHConstructProps {
  /**
   * The namespace where the service will be created
   */
  namespace: string;
  
  /**
   * The base name for the application (e.g., 'backstage', 'nextjs')
   */
  appName: string;
  
  /**
   * The environment name (e.g., 'dev', 'staging')
   */
  environment: string;
  
  /**
   * The NodePort to expose SSH on (must be in range 30000-32767)
   * We use a pattern: 30000 + app-specific offset
   * - backstage-dev: 30022
   * - backstage-staging: 30023
   * - nextjs-dev: 30024
   * - nextjs-staging: 30025
   * etc.
   */
  nodePort: number;
  
  /**
   * Additional labels to apply to the service
   */
  additionalLabels?: { [key: string]: string };
}

/**
 * A reusable construct for creating SSH services for DevSpace-enabled pods
 * 
 * This follows a standard pattern for exposing SSH access to development containers:
 * 1. Creates a NodePort service for SSH access
 * 2. Uses consistent labeling for easy identification
 * 3. Targets pods modified by DevSpace (with 'devspace.sh/replaced' label)
 * 
 * Usage:
 * ```typescript
 * new DevSpaceSSHConstruct(this, 'backstage-dev-ssh', {
 *   namespace: 'backstage',
 *   appName: 'backstage',
 *   environment: 'dev',
 *   nodePort: 30022
 * });
 * ```
 */
export class DevSpaceSSHConstruct extends Construct {
  public readonly service: k8s.KubeService;
  private readonly props: DevSpaceSSHConstructProps;
  
  constructor(scope: Construct, id: string, props: DevSpaceSSHConstructProps) {
    super(scope, id);
    this.props = props;
    
    const { namespace, appName, environment, nodePort, additionalLabels = {} } = props;
    
    // Validate NodePort range
    if (nodePort < 30000 || nodePort > 32767) {
      throw new Error(`NodePort ${nodePort} is outside valid range (30000-32767)`);
    }
    
    // Standard labels for all SSH services
    const labels = {
      app: `${appName}-${environment}`,
      environment: environment,
      'service-type': 'ssh',
      'devspace.sh/purpose': 'ssh-access',
      'cnoe.io/service-pattern': 'devspace-ssh',
      ...additionalLabels
    };
    
    // Create the SSH service
    this.service = new k8s.KubeService(this, 'service', {
      metadata: {
        name: `${appName}-${environment}-ssh`,
        namespace: namespace,
        labels: labels,
        annotations: {
          'devspace.sh/description': `SSH access for ${appName} ${environment} DevSpace development`,
          'cnoe.io/nodeport': nodePort.toString(),
          'cnoe.io/pattern': 'devspace-ssh-v1'
        }
      },
      spec: {
        type: 'NodePort',
        ports: [
          {
            name: 'ssh',
            port: 8022,  // DevSpace SSH always runs on 8022 inside the container
            targetPort: k8s.IntOrString.fromNumber(8022),
            nodePort: nodePort
          }
        ],
        selector: {
          app: `${appName}-${environment}`,
          environment: environment,
          'devspace.sh/replaced': 'true'  // Only target DevSpace-modified pods
        }
      }
    });
  }
  
  /**
   * Get the SSH connection string for this service
   */
  public getConnectionString(host: string = 'localhost'): string {
    const { nodePort } = this.props;
    return `ssh -p ${nodePort} devspace@${host}`;
  }
  
  /**
   * Get the VS Code Remote SSH configuration entry
   */
  public getVSCodeConfig(): string {
    const { nodePort, appName, environment } = this.props;
    const name = `${appName}-${environment}-ssh`;
    return `Host ${name}
  HostName localhost
  Port ${nodePort}
  User devspace
  IdentityFile ~/.devspace/ssh/id_devspace_ecdsa
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null`;
  }
}

/**
 * Helper class to manage NodePort allocations
 * Ensures consistent port assignments across environments
 */
export class SSHNodePortAllocator {
  private static readonly BASE_PORT = 30000;
  private static readonly allocations = new Map<string, number>([
    // Pre-allocated ports for common services
    ['backstage-dev', 30022],
    ['backstage-staging', 30023],
    ['nextjs-dev', 30024],
    ['nextjs-staging', 30025],
    ['postgres-dev', 30026],
    ['postgres-staging', 30027],
    // Add more as needed
  ]);
  
  /**
   * Get or allocate a NodePort for a service
   */
  public static getPort(appName: string, environment: string): number {
    const key = `${appName}-${environment}`;
    
    if (this.allocations.has(key)) {
      return this.allocations.get(key)!;
    }
    
    // Auto-allocate starting from 30100 for unregistered services
    const autoPort = 30100 + Array.from(this.allocations.keys()).filter(k => !this.allocations.has(k)).length;
    this.allocations.set(key, autoPort);
    
    return autoPort;
  }
  
  /**
   * Register a custom port allocation
   */
  public static registerPort(appName: string, environment: string, port: number): void {
    const key = `${appName}-${environment}`;
    this.allocations.set(key, port);
  }
  
  /**
   * Get all allocations for documentation
   */
  public static getAllocations(): Map<string, number> {
    return new Map(this.allocations);
  }
}