import { Chart } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import { WorkflowTemplate } from '../../imports/argoproj.io';
import { defaultKubectlImage } from '../../config/images';

export class DaggerInfraChart extends Chart {
  constructor(scope: Construct, id: string) {
    super(scope, id);

    const ns = 'argo';

    // Note: ServiceAccount 'argo-workflow' is created by the argo-workflows Helm chart
    // We only need to create the additional RBAC resources

    // Role for Argo Workflows
    new k8s.KubeRole(this, 'argo-workflow-role', {
      metadata: { 
        name: 'argo-workflow-role', 
        namespace: ns 
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['pods', 'pods/exec', 'pods/log'],
          verbs: ['create', 'delete', 'get', 'list', 'patch', 'update', 'watch']
        },
        {
          apiGroups: [''],
          resources: ['configmaps'],
          verbs: ['get', 'list', 'watch']
        },
        {
          apiGroups: [''],
          resources: ['persistentvolumeclaims'],
          verbs: ['create', 'delete', 'get', 'list', 'update', 'watch']
        },
        {
          apiGroups: ['argoproj.io'],
          resources: [
            'workflows',
            'workflows/finalizers',
            'workflowtasksets',
            'workflowtasksets/finalizers',
            'workflowtemplates',
            'workflowtemplaterefs'
          ],
          verbs: ['create', 'delete', 'get', 'list', 'patch', 'update', 'watch']
        }
      ]
    });

    // RoleBinding
    new k8s.KubeRoleBinding(this, 'argo-workflow-rb', {
      metadata: { 
        name: 'argo-workflow-binding', 
        namespace: ns 
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'Role',
        name: 'argo-workflow-role'
      },
      subjects: [{
        kind: 'ServiceAccount',
        name: 'argo-workflow',
        namespace: ns
      }]
    });

    // Dagger Build WorkflowTemplate
    new WorkflowTemplate(this, 'dagger-build-template', {
      metadata: {
        name: 'dagger-build-template',
        namespace: ns,
        labels: {
          'app.kubernetes.io/component': 'workflow-template',
          'app.kubernetes.io/part-of': 'dagger',
          'app.kubernetes.io/name': 'dagger-build-template'
        }
      },
      spec: {
        entrypoint: 'dagger-build',
        serviceAccountName: 'argo-workflow',
        templates: [
          {
            name: 'dagger-build',
            inputs: {
              parameters: [
                {
                  name: 'repo-url',
                  description: 'Git repository URL'
                },
                {
                  name: 'branch',
                  default: 'main',
                  description: 'Git branch to build'
                },
                {
                  name: 'image-name',
                  description: 'Docker image name to build'
                },
                {
                  name: 'registry',
                  default: 'localhost:5000',
                  description: 'Container registry URL'
                }
              ]
            },
            container: {
              image: 'registry.dagger.io/dagger:latest',
              command: ['sh', '-c'],
              args: [
                `git clone {{inputs.parameters.repo-url}} /workspace && \
                cd /workspace && \
                git checkout {{inputs.parameters.branch}} && \
                dagger run build --push {{inputs.parameters.registry}}/{{inputs.parameters.image-name}}:{{workflow.name}}`
              ],
              volumeMounts: [
                {
                  name: 'dagger-engine',
                  mountPath: '/var/run/docker.sock'
                }
              ],
              env: [
                {
                  name: 'DAGGER_CLOUD_TOKEN',
                  valueFrom: {
                    secretKeyRef: {
                      name: 'dagger-cloud-token',
                      key: 'token',
                      optional: true
                    }
                  }
                }
              ]
            },
            volumes: [
              {
                name: 'dagger-engine',
                hostPath: {
                  path: '/var/run/docker.sock',
                  type: 'Socket'
                }
              }
            ]
          }
        ]
      }
    });

    // Dagger Test WorkflowTemplate
    new WorkflowTemplate(this, 'dagger-test-template', {
      metadata: {
        name: 'dagger-test-template',
        namespace: ns,
        labels: {
          'app.kubernetes.io/component': 'workflow-template',
          'app.kubernetes.io/part-of': 'dagger',
          'app.kubernetes.io/name': 'dagger-test-template'
        }
      },
      spec: {
        entrypoint: 'dagger-test',
        serviceAccountName: 'argo-workflow',
        templates: [
          {
            name: 'dagger-test',
            inputs: {
              parameters: [
                {
                  name: 'repo-url',
                  description: 'Git repository URL'
                },
                {
                  name: 'branch',
                  default: 'main',
                  description: 'Git branch to test'
                },
                {
                  name: 'test-command',
                  default: 'test',
                  description: 'Dagger command to run tests'
                }
              ]
            },
            container: {
              image: 'registry.dagger.io/dagger:latest',
              command: ['sh', '-c'],
              args: [
                `git clone {{inputs.parameters.repo-url}} /workspace && \
                cd /workspace && \
                git checkout {{inputs.parameters.branch}} && \
                dagger run {{inputs.parameters.test-command}}`
              ],
              volumeMounts: [
                {
                  name: 'dagger-engine',
                  mountPath: '/var/run/docker.sock'
                }
              ]
            },
            volumes: [
              {
                name: 'dagger-engine',
                hostPath: {
                  path: '/var/run/docker.sock',
                  type: 'Socket'
                }
              }
            ]
          }
        ]
      }
    });

    // Backstage-specific Dagger Build WorkflowTemplate
    new WorkflowTemplate(this, 'dagger-backstage-build-template', {
      metadata: {
        name: 'dagger-backstage-build-template',
        namespace: ns,
        labels: {
          'app.kubernetes.io/component': 'workflow-template',
          'app.kubernetes.io/part-of': 'dagger',
          'app.kubernetes.io/name': 'dagger-backstage-build-template'
        }
      },
      spec: {
        entrypoint: 'backstage-build-deploy',
        serviceAccountName: 'argo-workflow',
        templates: [
          {
            name: 'backstage-build-deploy',
            inputs: {
              parameters: [
                {
                  name: 'git-url',
                  default: 'https://gitea.cnoe.localtest.me:8443/giteaadmin/backstage-cnoe.git'
                },
                {
                  name: 'branch',
                  default: 'main'
                },
                {
                  name: 'registry',
                  default: 'localhost:5000'
                },
                {
                  name: 'image-tag',
                  default: 'latest'
                }
              ]
            },
            dag: {
              tasks: [
                {
                  name: 'clone-repo',
                  template: 'git-clone',
                  arguments: {
                    parameters: [
                      { name: 'repo-url', value: '{{inputs.parameters.git-url}}' },
                      { name: 'branch', value: '{{inputs.parameters.branch}}' }
                    ]
                  }
                },
                {
                  name: 'build-image',
                  template: 'dagger-build-backstage',
                  dependencies: ['clone-repo'],
                  arguments: {
                    parameters: [
                      { name: 'registry', value: '{{inputs.parameters.registry}}' },
                      { name: 'image-tag', value: '{{inputs.parameters.image-tag}}' }
                    ]
                  }
                },
                {
                  name: 'deploy-to-kind',
                  template: 'kubectl-apply',
                  dependencies: ['build-image'],
                  arguments: {
                    parameters: [
                      { name: 'image', value: '{{inputs.parameters.registry}}/backstage:{{inputs.parameters.image-tag}}' }
                    ]
                  }
                }
              ]
            }
          },
          {
            name: 'git-clone',
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
            name: 'dagger-build-backstage',
            inputs: {
              parameters: [
                { name: 'registry' },
                { name: 'image-tag' }
              ]
            },
            container: {
              image: 'registry.dagger.io/dagger:latest',
              command: ['sh', '-c'],
              args: [
                `cd /workspace && \
                dagger run build --dockerfile=./Dockerfile \
                --push {{inputs.parameters.registry}}/backstage:{{inputs.parameters.image-tag}}`
              ],
              volumeMounts: [
                {
                  name: 'workspace',
                  mountPath: '/workspace'
                },
                {
                  name: 'dagger-engine',
                  mountPath: '/var/run/docker.sock'
                }
              ]
            }
          },
          {
            name: 'kubectl-apply',
            inputs: {
              parameters: [
                { name: 'image' }
              ]
            },
            container: {
              image: defaultKubectlImage,
              command: ['sh', '-c'],
              args: [
                `kubectl set image deployment/backstage backstage={{inputs.parameters.image}} -n backstage`
              ]
            }
          }
        ],
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
        volumes: [
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
