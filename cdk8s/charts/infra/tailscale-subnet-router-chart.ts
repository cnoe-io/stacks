import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export interface TailscaleSubnetRouterChartProps extends ChartProps {
  /**
   * Namespace to deploy the subnet router
   * @default 'tailscale'
   */
  namespace?: string;

  /**
   * CIDR ranges to advertise as subnet routes
   * @default ['10.244.0.0/16', '10.96.0.0/16'] (Kind cluster pod and service CIDRs)
   */
  routes?: string[];

  /**
   * Name of the secret containing the Tailscale auth key
   * @default 'tailscale-auth-key'
   */
  authKeySecretName?: string;

  /**
   * Key name within the auth key secret
   * @default 'authKey'
   */
  authKeySecretKey?: string;

  /**
   * ServiceAccount name to use
   * @default 'operator'
   */
  serviceAccountName?: string;
}

/**
 * Chart for deploying a Tailscale subnet router in Kubernetes
 *
 * This allows exposing the entire Kubernetes cluster network (pods and services)
 * to your Tailscale network, enabling direct access to cluster IPs from any
 * Tailscale-connected device.
 *
 * Prerequisites:
 * - Tailscale auth key stored in a Kubernetes secret
 * - ServiceAccount with permissions to read/update the auth key secret
 *
 * After deployment:
 * - Routes must be approved in Tailscale admin console
 * - Linux clients need to run: tailscale set --accept-routes
 */
export class TailscaleSubnetRouterChart extends Chart {
  constructor(scope: Construct, id: string, props: TailscaleSubnetRouterChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || 'tailscale';
    const routes = props.routes || ['10.244.0.0/16', '10.96.0.0/16'];
    const authKeySecretName = props.authKeySecretName || 'tailscale-auth-key';
    const authKeySecretKey = props.authKeySecretKey || 'authKey';
    const serviceAccountName = props.serviceAccountName || 'tailscale-subnet-router';

    // Create ServiceAccount for subnet router
    new k8s.KubeServiceAccount(this, 'service-account', {
      metadata: {
        name: serviceAccountName,
        namespace,
        labels: {
          app: 'tailscale-subnet-router',
        },
      },
    });

    // Create Role for managing state secret
    new k8s.KubeRole(this, 'role', {
      metadata: {
        name: 'tailscale-subnet-router',
        namespace,
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['secrets'],
          verbs: ['get', 'create', 'update', 'patch'],
        },
      ],
    });

    // Create RoleBinding
    new k8s.KubeRoleBinding(this, 'role-binding', {
      metadata: {
        name: 'tailscale-subnet-router',
        namespace,
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'Role',
        name: 'tailscale-subnet-router',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: serviceAccountName,
          namespace,
        },
      ],
    });

    // Create the subnet router pod
    new k8s.KubePod(this, 'subnet-router', {
      metadata: {
        name: 'tailscale-subnet-router',
        namespace,
        labels: {
          app: 'tailscale-subnet-router',
          'app.kubernetes.io/name': 'tailscale-subnet-router',
          'app.kubernetes.io/component': 'subnet-router',
        },
      },
      spec: {
        serviceAccountName,
        containers: [
          {
            name: 'tailscale',
            image: 'ghcr.io/tailscale/tailscale:latest',
            env: [
              {
                name: 'TS_KUBE_SECRET',
                value: 'tailscale-subnet-state',
              },
              {
                name: 'TS_AUTHKEY',
                valueFrom: {
                  secretKeyRef: {
                    name: authKeySecretName,
                    key: authKeySecretKey,
                  },
                },
              },
              {
                name: 'TS_ROUTES',
                value: routes.join(','),
              },
              {
                name: 'TS_USERSPACE',
                value: 'true', // Required for containers (no kernel modules)
              },
              {
                name: 'TS_ACCEPT_DNS',
                value: 'false',
              },
              {
                name: 'TS_STATE_DIR',
                value: '/tmp',
              },
            ],
            securityContext: {
              runAsUser: 1000,
              runAsGroup: 1000,
            },
          },
        ],
      },
    });
  }
}
