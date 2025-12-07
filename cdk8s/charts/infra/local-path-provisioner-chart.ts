/**
 * LocalPathProvisionerChart - Dynamic local storage provisioner for Talos Linux
 * Feature: 102-bootstrap-talos-argocd
 *
 * Provides dynamic local storage provisioning using Rancher's local-path-provisioner.
 * This is essential for Talos clusters which don't have a default storage class.
 *
 * Based on: https://github.com/rancher/local-path-provisioner
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export interface LocalPathProvisionerChartProps extends ChartProps {
  /**
   * Storage path on nodes
   * @default '/opt/local-path-provisioner'
   */
  storagePath?: string;

  /**
   * Make this the default storage class
   * @default true
   */
  isDefault?: boolean;

  /**
   * Provisioner image
   * @default 'rancher/local-path-provisioner:v0.0.26'
   */
  image?: string;

  /**
   * Helper image for setup/teardown
   * @default 'busybox:latest'
   */
  helperImage?: string;
}

export class LocalPathProvisionerChart extends Chart {
  constructor(scope: Construct, id: string, props: LocalPathProvisionerChartProps = {}) {
    super(scope, id, props);

    const namespace = 'local-path-storage';
    const storagePath = props.storagePath || '/opt/local-path-provisioner';
    const isDefault = props.isDefault !== false;
    const image = props.image || 'rancher/local-path-provisioner:v0.0.26';
    const helperImage = props.helperImage || 'busybox:latest';

    // Namespace
    new k8s.KubeNamespace(this, 'namespace', {
      metadata: {
        name: namespace,
        labels: {
          'app.kubernetes.io/name': 'local-path-provisioner',
          'app.kubernetes.io/component': 'storage',
        },
      },
    });

    // ServiceAccount
    new k8s.KubeServiceAccount(this, 'sa', {
      metadata: {
        name: 'local-path-provisioner-service-account',
        namespace,
      },
    });

    // ClusterRole
    new k8s.KubeClusterRole(this, 'cluster-role', {
      metadata: {
        name: 'local-path-provisioner-role',
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['nodes', 'persistentvolumeclaims', 'configmaps', 'pods', 'pods/log'],
          verbs: ['get', 'list', 'watch'],
        },
        {
          apiGroups: [''],
          resources: ['persistentvolumes'],
          verbs: ['get', 'list', 'watch', 'create', 'patch', 'update', 'delete'],
        },
        {
          apiGroups: [''],
          resources: ['events'],
          verbs: ['create', 'patch'],
        },
        {
          apiGroups: ['storage.k8s.io'],
          resources: ['storageclasses'],
          verbs: ['get', 'list', 'watch'],
        },
      ],
    });

    // ClusterRoleBinding
    new k8s.KubeClusterRoleBinding(this, 'cluster-role-binding', {
      metadata: {
        name: 'local-path-provisioner-bind',
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: 'local-path-provisioner-role',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: 'local-path-provisioner-service-account',
          namespace,
        },
      ],
    });

    // Role for namespace operations
    new k8s.KubeRole(this, 'role', {
      metadata: {
        name: 'local-path-provisioner-role',
        namespace,
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['pods'],
          verbs: ['get', 'list', 'watch', 'create', 'patch', 'update', 'delete'],
        },
      ],
    });

    // RoleBinding
    new k8s.KubeRoleBinding(this, 'role-binding', {
      metadata: {
        name: 'local-path-provisioner-bind',
        namespace,
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'Role',
        name: 'local-path-provisioner-role',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: 'local-path-provisioner-service-account',
          namespace,
        },
      ],
    });

    // ConfigMap for provisioner configuration
    new k8s.KubeConfigMap(this, 'config', {
      metadata: {
        name: 'local-path-config',
        namespace,
      },
      data: {
        'config.json': JSON.stringify({
          nodePathMap: [
            {
              node: 'DEFAULT_PATH_FOR_NON_LISTED_NODES',
              paths: [storagePath],
            },
          ],
        }),
        'setup': `#!/bin/sh
set -eu
mkdir -m 0777 -p "$VOL_DIR"
`,
        'teardown': `#!/bin/sh
set -eu
rm -rf "$VOL_DIR"
`,
        'helperPod.yaml': `apiVersion: v1
kind: Pod
metadata:
  name: helper-pod
spec:
  priorityClassName: system-node-critical
  tolerations:
    - key: node.kubernetes.io/disk-pressure
      operator: Exists
      effect: NoSchedule
  containers:
  - name: helper-pod
    image: ${helperImage}
    imagePullPolicy: IfNotPresent
`,
      },
    });

    // Deployment
    new k8s.KubeDeployment(this, 'deployment', {
      metadata: {
        name: 'local-path-provisioner',
        namespace,
        labels: {
          'app.kubernetes.io/name': 'local-path-provisioner',
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            'app.kubernetes.io/name': 'local-path-provisioner',
          },
        },
        template: {
          metadata: {
            labels: {
              'app.kubernetes.io/name': 'local-path-provisioner',
            },
          },
          spec: {
            serviceAccountName: 'local-path-provisioner-service-account',
            containers: [
              {
                name: 'local-path-provisioner',
                image,
                imagePullPolicy: 'IfNotPresent',
                command: [
                  'local-path-provisioner',
                  '--debug',
                  'start',
                  '--config',
                  '/etc/config/config.json',
                ],
                env: [
                  {
                    name: 'POD_NAMESPACE',
                    valueFrom: {
                      fieldRef: {
                        fieldPath: 'metadata.namespace',
                      },
                    },
                  },
                  {
                    name: 'CONFIG_MOUNT_PATH',
                    value: '/etc/config/',
                  },
                ],
                volumeMounts: [
                  {
                    name: 'config-volume',
                    mountPath: '/etc/config/',
                  },
                ],
                resources: {
                  requests: {
                    cpu: k8s.Quantity.fromString('10m'),
                    memory: k8s.Quantity.fromString('64Mi'),
                  },
                  limits: {
                    cpu: k8s.Quantity.fromString('100m'),
                    memory: k8s.Quantity.fromString('128Mi'),
                  },
                },
              },
            ],
            volumes: [
              {
                name: 'config-volume',
                configMap: {
                  name: 'local-path-config',
                },
              },
            ],
          },
        },
      },
    });

    // StorageClass - this is the key resource
    new k8s.KubeStorageClass(this, 'storage-class', {
      metadata: {
        name: 'local-path',
        annotations: isDefault
          ? {
              'storageclass.kubernetes.io/is-default-class': 'true',
            }
          : undefined,
      },
      provisioner: 'rancher.io/local-path',
      volumeBindingMode: 'WaitForFirstConsumer',
      reclaimPolicy: 'Delete',
    });
  }
}
