import { Chart } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import { WorkflowTemplate } from '../../imports/argoproj.io';
import { defaultKubectlImage } from '../../config/images';

export interface DaggerPipelineChartProps {
  namespace?: string;
  registryUrl?: string;
  enableCloudToken?: boolean;
}

export class DaggerPipelineChart extends Chart {
  constructor(scope: Construct, id: string, props: DaggerPipelineChartProps = {}) {
    super(scope, id);

    const ns = props.namespace || 'argo';
    const registryUrl = props.registryUrl || 'localhost:5000';

    // ConfigMap with Dagger pipeline scripts
    new k8s.KubeConfigMap(this, 'dagger-pipeline-scripts', {
      metadata: {
        name: 'dagger-pipeline-scripts',
        namespace: ns,
        labels: {
          'app.kubernetes.io/component': 'pipeline-scripts',
          'app.kubernetes.io/part-of': 'dagger',
          'app.kubernetes.io/name': 'dagger-pipeline-scripts'
        }
      },
      data: {
        'build.sh': `#!/bin/sh
set -e

# Dagger build script for generic applications
echo "Starting Dagger build..."

# Initialize Dagger
dagger init

# Create build function
cat > build.cue <<EOF
package main

import (
    "dagger.io/dagger"
    "dagger.io/dagger/core"
)

#Build: {
    source: dagger.#Artifact
    dockerfile: string | *"Dockerfile"
    
    build: core.#Build & {
        steps: [
            core.#Copy & {
                input: dagger.#Scratch
                contents: source
                dest: "/src"
            },
            core.#Dockerfile & {
                source: "/src"
                path: dockerfile
            }
        ]
    }
}
EOF

# Run the build
dagger do build

echo "Build completed successfully"
`,
        'test.sh': `#!/bin/sh
set -e

# Dagger test script
echo "Starting Dagger tests..."

# Run tests based on detected framework
if [ -f "package.json" ]; then
    echo "Detected Node.js project"
    dagger do test --with 'npm test'
elif [ -f "go.mod" ]; then
    echo "Detected Go project"
    dagger do test --with 'go test ./...'
elif [ -f "Cargo.toml" ]; then
    echo "Detected Rust project"
    dagger do test --with 'cargo test'
else
    echo "Running generic test command"
    dagger do test
fi

echo "Tests completed successfully"
`,
        'deploy.sh': `#!/bin/sh
set -e

# Dagger deployment script
echo "Starting deployment with Dagger..."

REGISTRY="\${REGISTRY:-localhost:5000}"
IMAGE_NAME="\${IMAGE_NAME:-app}"
IMAGE_TAG="\${IMAGE_TAG:-latest}"

# Build and push image
dagger do build --push "\${REGISTRY}/\${IMAGE_NAME}:\${IMAGE_TAG}"

# Update Kubernetes deployment
kubectl set image deployment/\${IMAGE_NAME} \${IMAGE_NAME}="\${REGISTRY}/\${IMAGE_NAME}:\${IMAGE_TAG}" -n \${NAMESPACE:-default}

echo "Deployment completed successfully"
`
      }
    });

    // Secret for Dagger Cloud token (if enabled)
    if (props.enableCloudToken) {
      new k8s.KubeSecret(this, 'dagger-cloud-token', {
        metadata: {
          name: 'dagger-cloud-token',
          namespace: ns,
          labels: {
            'app.kubernetes.io/component': 'credentials',
            'app.kubernetes.io/part-of': 'dagger',
            'app.kubernetes.io/name': 'dagger-cloud-token'
          }
        },
        stringData: {
          token: 'REPLACE_WITH_ACTUAL_TOKEN'
        }
      });
    }

    // Workflow for CI/CD Pipeline using Dagger
    new WorkflowTemplate(this, 'dagger-cicd-workflow', {
      metadata: {
        name: 'dagger-cicd-pipeline',
        namespace: ns,
        labels: {
          'app.kubernetes.io/component': 'workflow-template',
          'app.kubernetes.io/part-of': 'dagger',
          'app.kubernetes.io/name': 'dagger-cicd-pipeline'
        }
      },
      spec: {
        entrypoint: 'cicd-pipeline',
        serviceAccountName: 'argo-workflow',
        volumeClaimTemplates: [
          {
            metadata: {
              name: 'workspace'
            },
            spec: {
              accessModes: ['ReadWriteOnce'],
              resources: {
                requests: {
                  storage: '10Gi'
                }
              }
            }
          }
        ],
        templates: [
          {
            name: 'cicd-pipeline',
            inputs: {
              parameters: [
                {
                  name: 'repo-url',
                  description: 'Git repository URL'
                },
                {
                  name: 'branch',
                  default: 'main',
                  description: 'Git branch'
                },
                {
                  name: 'app-name',
                  description: 'Application name'
                },
                {
                  name: 'namespace',
                  default: 'default',
                  description: 'Kubernetes namespace'
                }
              ]
            },
            dag: {
              tasks: [
                {
                  name: 'checkout',
                  template: 'git-checkout',
                  arguments: {
                    parameters: [
                      { name: 'repo-url', value: '{{inputs.parameters.repo-url}}' },
                      { name: 'branch', value: '{{inputs.parameters.branch}}' }
                    ]
                  }
                },
                {
                  name: 'test',
                  template: 'dagger-test',
                  dependencies: ['checkout']
                },
                {
                  name: 'build',
                  template: 'dagger-build',
                  dependencies: ['test'],
                  arguments: {
                    parameters: [
                      { name: 'app-name', value: '{{inputs.parameters.app-name}}' }
                    ]
                  }
                },
                {
                  name: 'deploy',
                  template: 'dagger-deploy',
                  dependencies: ['build'],
                  arguments: {
                    parameters: [
                      { name: 'app-name', value: '{{inputs.parameters.app-name}}' },
                      { name: 'namespace', value: '{{inputs.parameters.namespace}}' }
                    ]
                  }
                }
              ]
            }
          },
          {
            name: 'git-checkout',
            inputs: {
              parameters: [
                { name: 'repo-url' },
                { name: 'branch' }
              ]
            },
            container: {
              image: 'alpine/git:latest',
              command: ['sh', '-c'],
              args: [
                'git clone {{inputs.parameters.repo-url}} /workspace && cd /workspace && git checkout {{inputs.parameters.branch}}'
              ],
              volumeMounts: [
                {
                  name: 'workspace',
                  mountPath: '/workspace'
                }
              ]
            }
          },
          {
            name: 'dagger-test',
            container: {
              image: 'registry.dagger.io/dagger:latest',
              command: ['sh', '-c'],
              args: ['cd /workspace && /scripts/test.sh'],
              volumeMounts: [
                {
                  name: 'workspace',
                  mountPath: '/workspace'
                },
                {
                  name: 'scripts',
                  mountPath: '/scripts'
                },
                {
                  name: 'dagger-engine',
                  mountPath: '/var/run/docker.sock'
                }
              ]
            }
          },
          {
            name: 'dagger-build',
            inputs: {
              parameters: [
                { name: 'app-name' }
              ]
            },
            container: {
              image: 'registry.dagger.io/dagger:latest',
              command: ['sh', '-c'],
              args: ['cd /workspace && IMAGE_NAME={{inputs.parameters.app-name}} /scripts/build.sh'],
              env: [
                {
                  name: 'REGISTRY',
                  value: registryUrl
                }
              ],
              volumeMounts: [
                {
                  name: 'workspace',
                  mountPath: '/workspace'
                },
                {
                  name: 'scripts',
                  mountPath: '/scripts'
                },
                {
                  name: 'dagger-engine',
                  mountPath: '/var/run/docker.sock'
                }
              ]
            }
          },
          {
            name: 'dagger-deploy',
            inputs: {
              parameters: [
                { name: 'app-name' },
                { name: 'namespace' }
              ]
            },
            container: {
              image: 'registry.dagger.io/dagger:latest',
              command: ['sh', '-c'],
              args: ['IMAGE_NAME={{inputs.parameters.app-name}} NAMESPACE={{inputs.parameters.namespace}} /scripts/deploy.sh'],
              env: [
                {
                  name: 'REGISTRY',
                  value: registryUrl
                }
              ],
              volumeMounts: [
                {
                  name: 'scripts',
                  mountPath: '/scripts'
                },
                {
                  name: 'dagger-engine',
                  mountPath: '/var/run/docker.sock'
                }
              ]
            }
          }
        ],
        volumes: [
          {
            name: 'scripts',
            configMap: {
              name: 'dagger-pipeline-scripts',
              defaultMode: 0o755
            }
          },
          {
            name: 'dagger-engine',
            hostPath: {
              path: '/var/run/docker.sock',
              type: 'Socket'
            }
          }
        ]
      }
    });

    // Backstage-specific pipeline with local registry
    new WorkflowTemplate(this, 'dagger-backstage-local-pipeline', {
      metadata: {
        name: 'dagger-backstage-local-pipeline',
        namespace: ns,
        labels: {
          'app.kubernetes.io/component': 'workflow-template',
          'app.kubernetes.io/part-of': 'dagger',
          'app.kubernetes.io/name': 'dagger-backstage-local-pipeline'
        }
      },
      spec: {
        entrypoint: 'backstage-dev-pipeline',
        serviceAccountName: 'argo-workflow',
        templates: [
          {
            name: 'backstage-dev-pipeline',
            inputs: {
              parameters: [
                {
                  name: 'source-path',
                  default: '/home/vscode/workspace/backstage-cnoe',
                  description: 'Local source path'
                },
                {
                  name: 'image-tag',
                  default: 'dev-{{workflow.creationTimestamp.Y}}{{workflow.creationTimestamp.m}}{{workflow.creationTimestamp.d}}-{{workflow.creationTimestamp.H}}{{workflow.creationTimestamp.M}}{{workflow.creationTimestamp.S}}',
                  description: 'Image tag'
                }
              ]
            },
            steps: [
              [
                {
                  name: 'build-push-local',
                  template: 'dagger-build-local',
                  arguments: {
                    parameters: [
                      { name: 'source-path', value: '{{inputs.parameters.source-path}}' },
                      { name: 'image-tag', value: '{{inputs.parameters.image-tag}}' }
                    ]
                  }
                }
              ],
              [
                {
                  name: 'update-deployment',
                  template: 'kubectl-update',
                  arguments: {
                    parameters: [
                      { name: 'image', value: `${registryUrl}/backstage:{{inputs.parameters.image-tag}}` }
                    ]
                  }
                }
              ]
            ]
          },
          {
            name: 'dagger-build-local',
            inputs: {
              parameters: [
                { name: 'source-path' },
                { name: 'image-tag' }
              ]
            },
            container: {
              image: 'registry.dagger.io/dagger:latest',
              command: ['sh', '-c'],
              args: [
                `dagger run build \
                --source {{inputs.parameters.source-path}} \
                --dockerfile {{inputs.parameters.source-path}}/Dockerfile \
                --push ${registryUrl}/backstage:{{inputs.parameters.image-tag}}`
              ],
              volumeMounts: [
                {
                  name: 'source',
                  mountPath: '{{inputs.parameters.source-path}}',
                  readOnly: true
                },
                {
                  name: 'dagger-engine',
                  mountPath: '/var/run/docker.sock'
                }
              ]
            }
          },
          {
            name: 'kubectl-update',
            inputs: {
              parameters: [
                { name: 'image' }
              ]
            },
            container: {
              image: defaultKubectlImage,
              command: ['kubectl'],
              args: [
                'set', 'image',
                'deployment/backstage',
                'backstage={{inputs.parameters.image}}',
                '-n', 'backstage'
              ]
            }
          }
        ],
        volumes: [
          {
            name: 'source',
            hostPath: {
              path: '/home/vscode/workspace/backstage-cnoe',
              type: 'Directory'
            }
          },
          {
            name: 'dagger-engine',
            hostPath: {
              path: '/var/run/docker.sock',
              type: 'Socket'
            }
          }
        ]
      }
    });
  }
}
