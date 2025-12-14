import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { Project, ProjectConfig } from '../../imports/kargo.akuity.io';
import * as k8s from '../../imports/k8s';

/**
 * Kargo Pipelines Project Chart
 * Creates a central Kargo project that contains all image promotion pipelines
 */
export class KargoPipelinesProjectChart extends Chart {
  constructor(scope: Construct, id: string, props?: ChartProps) {
    super(scope, id, props);

    // Create/ensure the namespace with the required Kargo label
    // Using a patch to ensure labels are applied even if namespace exists
    new k8s.KubeNamespace(this, 'pipelines-namespace', {
      metadata: {
        name: 'kargo-pipelines',
        annotations: { 'argocd.argoproj.io/sync-wave': '-15' },
        labels: {
          'app.kubernetes.io/name': 'kargo-pipelines',
          'app.kubernetes.io/part-of': 'kargo',
          'app.kubernetes.io/component': 'namespace',
          'kargo.akuity.io/project': 'true'
        }
      }
    });

    // Create the central Kargo Project
    // Now that namespace is guaranteed to have the label, this will succeed
    new Project(this, 'pipelines-project', {
      metadata: {
        name: 'kargo-pipelines',
        annotations: {
          'argocd.argoproj.io/sync-wave': '-10'  // Create Project first
        },
        labels: {
          'app.kubernetes.io/name': 'kargo-pipelines',
          'app.kubernetes.io/part-of': 'kargo',
          'app.kubernetes.io/component': 'project'
        }
      }
      // No spec field - Kargo Project v1alpha1 doesn't have a spec
    });

    // Create ProjectConfig for promotion policies
    new ProjectConfig(this, 'pipelines-project-config', {
      metadata: {
        name: 'kargo-pipelines',
        namespace: 'kargo-pipelines',
        annotations: {
          'argocd.argoproj.io/sync-wave': '0'  // After namespace exists
        },
        labels: {
          'app.kubernetes.io/name': 'kargo-pipelines-config',
          'app.kubernetes.io/part-of': 'kargo',
          'app.kubernetes.io/component': 'project-config'
        }
      },
      spec: {
        promotionPolicies: [
          // Inner Loop: Auto-promote to local-dev stages (rapid iteration)
          {
            stageSelector: {
              name: 'glob:*-local-dev'
            },
            autoPromotionEnabled: true
          },
          // Outer Loop: Auto-promote to dev stages
          {
            stageSelector: {
              name: 'glob:*-dev'
            },
            autoPromotionEnabled: true
          },
          // Outer Loop: Manual promotion for staging
          {
            stageSelector: {
              name: 'glob:*-staging'
            },
            autoPromotionEnabled: false
          },
          // Outer Loop: Manual promotion for production
          {
            stageSelector: {
              name: 'glob:*-prod'
            },
            autoPromotionEnabled: false
          }
        ],
        // Configure webhook receivers for instant image detection
        // Both Gitea and GitHub use the github webhook receiver type
        // (Gitea implements GitHub-compatible webhook format)
        webhookReceivers: [
          // Gitea webhook for inner loop (in-cluster, rapid iteration)
          {
            name: 'gitea-backstage',
            github: {
              secretRef: {
                name: 'kargo-gitea-webhook-secret'
              }
            }
          },
          // GitHub webhook for outer loop (external CI-built images)
          {
            name: 'github-backstage',
            github: {
              secretRef: {
                name: 'kargo-github-webhook-secret'
              }
            }
          }
        ]
      }
    });

    // Create webhook secret for Gitea integration
    // This secret will be used to authenticate webhook calls from Gitea
    new k8s.KubeSecret(this, 'gitea-webhook-secret', {
      metadata: {
        name: 'kargo-gitea-webhook-secret',
        namespace: 'kargo-pipelines',
        annotations: {
          'argocd.argoproj.io/sync-wave': '5'  // After namespace and project config
        },
        labels: {
          'app.kubernetes.io/name': 'kargo-gitea-webhook',
          'app.kubernetes.io/part-of': 'kargo-pipelines',
          'app.kubernetes.io/component': 'webhook-secret'
        }
      },
      stringData: {
        // Secure webhook secret for Gitea authentication
        // In production, this should be stored in Azure Key Vault
        // The key must be named 'secret' for GitHub-compatible webhooks
        secret: 'lwxtOFx10Jrox11Zi40r3L3zEvR6J8q9',
        'setup-instructions.txt': `Gitea Webhook Setup Instructions
=============================

1. Generate a secure webhook secret:
   secret=$(openssl rand -base64 48 | tr -d '=+/' | head -c 32)
   echo "Webhook Secret: $secret"

2. Update this secret with the generated value:
   kubectl patch secret kargo-gitea-webhook-secret \\
     -n kargo-pipelines \\
     --type json \\
     -p='[{"op": "replace", "path": "/stringData/webhookSecret", "value": "'$secret'"}]'

3. Get the webhook receiver URL:
   kubectl get projectconfigs kargo-pipelines \\
     -n kargo-pipelines \\
     -o=jsonpath='{.status.webhookReceivers}'

4. Configure webhook in Gitea:
   - Go to your Gitea repository settings
   - Navigate to Webhooks
   - Add a new webhook with:
     - Target URL: <webhook receiver URL from step 3>
     - Secret: <secret from step 1>
     - Trigger on: Push Events
     - Active: Yes

5. Test the webhook:
   - Push a new image to the Gitea registry
   - Check Kargo warehouse for new freight
`
      }
    });

    // Create webhook secret for GitHub integration
    // This secret will be used to authenticate webhook calls from GitHub Actions
    new k8s.KubeSecret(this, 'github-webhook-secret', {
      metadata: {
        name: 'kargo-github-webhook-secret',
        namespace: 'kargo-pipelines',
        annotations: {
          'argocd.argoproj.io/sync-wave': '5'  // After namespace and project config
        },
        labels: {
          'app.kubernetes.io/name': 'kargo-github-webhook',
          'app.kubernetes.io/part-of': 'kargo-pipelines',
          'app.kubernetes.io/component': 'webhook-secret'
        }
      },
      stringData: {
        // Secure webhook secret for GitHub authentication
        // In production, this should be stored in Azure Key Vault
        // The key must be named 'secret' for GitHub-compatible webhooks
        secret: 'FzLfqJOXWWvzgxVNz6qLq6YuDp4g1BRm',
        'setup-instructions.txt': `GitHub Webhook Setup Instructions
===============================

1. Generate a secure webhook secret (or use the default one):
   secret=$(openssl rand -base64 48 | tr -d '=+/' | head -c 32)
   echo "Webhook Secret: $secret"

2. Update this secret with the generated value:
   kubectl patch secret kargo-github-webhook-secret \\
     -n kargo-pipelines \\
     --type json \\
     -p='[{"op": "replace", "path": "/stringData/secret", "value": "'$secret'"}]'

3. Get the webhook receiver URL:
   kubectl get projectconfigs kargo-pipelines \\
     -n kargo-pipelines \\
     -o=jsonpath='{.status.webhookReceivers}'

4. Configure webhook in GitHub repository:
   - Go to Repository Settings > Webhooks
   - Add a new webhook with:
     - Payload URL: <webhook receiver URL from step 3>
     - Content type: application/json
     - Secret: <secret from step 1>
     - Events: Select "Packages" or "push" events
     - Active: Yes

5. For external access (if not using Tailscale):
   - Expose the webhook endpoint via Ingress with TLS
   - GitHub requires HTTPS for webhook endpoints

6. Test the webhook:
   - Push a new tagged image to GHCR (e.g., ghcr.io/pittampalliorg/backstage:v1.0.0)
   - Check Kargo warehouse for new freight:
     kubectl get freights -n kargo-pipelines
`
      }
    });

    // Create shared RBAC resources for Git operations
    // Each pipeline will have its own service account but share common roles
    new k8s.KubeRole(this, 'kargo-git-role', {
      metadata: {
        name: 'kargo-git-promoter',
        namespace: 'kargo-pipelines',
        annotations: { 'argocd.argoproj.io/sync-wave': '10' }
      },
      rules: [
        { apiGroups: ['kargo.akuity.io'], resources: ['freights', 'stages', 'warehouses', 'promotions', 'projectconfigs'], verbs: ['get', 'list', 'watch', 'create', 'update', 'patch'] },
        { apiGroups: [''], resources: ['secrets', 'serviceaccounts'], verbs: ['get', 'list'] }
      ]
    });

    // Create a shared ClusterRole for ArgoCD operations
    new k8s.KubeClusterRole(this, 'kargo-argocd-updater-role', {
      metadata: {
        name: 'kargo-pipelines-argocd-updater',
        labels: {
          'app.kubernetes.io/name': 'kargo-pipelines-argocd-updater',
          'app.kubernetes.io/part-of': 'kargo-pipelines'
        }
      },
      rules: [ { apiGroups: ['argoproj.io'], resources: ['applications'], verbs: ['get', 'list', 'patch', 'update'] } ]
    });

    // Create a shared ClusterRoleBinding for all pipeline service accounts
    new k8s.KubeClusterRoleBinding(this, 'kargo-argocd-updater-binding', {
      metadata: {
        name: 'kargo-pipelines-argocd-updater',
        labels: {
          'app.kubernetes.io/name': 'kargo-pipelines-argocd-updater-binding',
          'app.kubernetes.io/part-of': 'kargo-pipelines'
        }
      },
      roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'ClusterRole', name: 'kargo-pipelines-argocd-updater' },
      subjects: [
        { kind: 'ServiceAccount', name: 'kargo-nextjs-git', namespace: 'kargo-pipelines' },
        { kind: 'ServiceAccount', name: 'kargo-backstage-git', namespace: 'kargo-pipelines' },
        { kind: 'ServiceAccount', name: 'kargo-controller', namespace: 'kargo' }
      ]
    });

    // Create RBAC for Kargo UI access
    // This allows authenticated users to view and manage the project
    new k8s.KubeClusterRoleBinding(this, 'kargo-admin-binding', {
      metadata: {
        name: 'kargo-admin-kargo-pipelines',
        labels: {
          'app.kubernetes.io/name': 'kargo-admin-binding',
          'app.kubernetes.io/part-of': 'kargo-pipelines'
        }
      },
      roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'ClusterRole', name: 'kargo-admin' },
      subjects: [
        { kind: 'User', name: 'system:serviceaccount:kargo:kargo-api' },
        { kind: 'Group', name: 'system:authenticated' }
      ]
    });

    // Create project-level admin binding
    new k8s.KubeRoleBinding(this, 'kargo-project-admin-binding', {
      metadata: {
        name: 'kargo-project-admin',
        namespace: 'kargo-pipelines',
        labels: {
          'app.kubernetes.io/name': 'kargo-project-admin-binding',
          'app.kubernetes.io/part-of': 'kargo-pipelines'
        }
      },
      roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'ClusterRole', name: 'kargo-project-admin' },
      subjects: [
        { kind: 'Group', name: 'system:authenticated' },
        { kind: 'ServiceAccount', name: 'kargo-api', namespace: 'kargo' },
        { kind: 'ServiceAccount', name: 'kargo-admin', namespace: 'kargo' }
      ]
    });
  }
}
