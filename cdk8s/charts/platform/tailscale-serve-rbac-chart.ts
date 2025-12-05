import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export interface TailscaleServeRbacChartProps extends ChartProps {
  /**
   * Namespace where RBAC resources will be created
   * @default 'tailscale'
   */
  namespace?: string;
}

/**
 * TailscaleServeRbacChart - Shared RBAC resources for all Tailscale Serve deployments
 *
 * This chart creates a single ServiceAccount, Role, and RoleBinding that are shared
 * by all *-tailscale-serve deployments. This eliminates SharedResourceWarning in ArgoCD
 * where multiple apps were managing the same RBAC resources.
 *
 * Sync wave: -45 (after tailscale-secrets at -70, before tailscale-serve apps at -40)
 */
export class TailscaleServeRbacChart extends Chart {
  constructor(scope: Construct, id: string, props: TailscaleServeRbacChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || 'tailscale';
    const serviceAccountName = 'tailscale-serve';

    // Create shared ServiceAccount for all tailscale-serve pods
    new k8s.KubeServiceAccount(this, 'sa', {
      metadata: {
        name: serviceAccountName,
        namespace,
        labels: {
          'app.kubernetes.io/name': 'tailscale-serve',
          'app.kubernetes.io/component': 'rbac',
          'app.kubernetes.io/part-of': 'tailscale',
        },
      },
    });

    // Shared Role to read secrets in the tailscale namespace
    new k8s.KubeRole(this, 'role', {
      metadata: {
        name: 'tailscale-serve-secret-reader',
        namespace,
        labels: {
          'app.kubernetes.io/name': 'tailscale-serve',
          'app.kubernetes.io/component': 'rbac',
          'app.kubernetes.io/part-of': 'tailscale',
        },
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['secrets'],
          verbs: ['get', 'list', 'watch'],
        },
      ],
    });

    // Bind the role to the ServiceAccount
    new k8s.KubeRoleBinding(this, 'role-binding', {
      metadata: {
        name: 'tailscale-serve-secret-reader',
        namespace,
        labels: {
          'app.kubernetes.io/name': 'tailscale-serve',
          'app.kubernetes.io/component': 'rbac',
          'app.kubernetes.io/part-of': 'tailscale',
        },
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'Role',
        name: 'tailscale-serve-secret-reader',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: serviceAccountName,
          namespace,
        },
      ],
    });
  }
}
