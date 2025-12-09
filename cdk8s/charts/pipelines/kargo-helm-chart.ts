import { Chart, ChartProps, Helm, ApiObject, JsonPatch } from 'cdk8s';
import { Construct } from 'constructs';
import { KubeNamespace, KubeSecret, KubeJob, KubeServiceAccount, KubeClusterRole, KubeClusterRoleBinding, Quantity, KubeIngress } from '../../imports/k8s';

export interface KargoHelmChartProps extends ChartProps {
  namespace?: string;
  /**
   * Skip mounting Gitea CA certificates.
   * Set to true for Talos clusters that use GitHub (valid SSL certs).
   * @default false
   */
  skipGiteaCACerts?: boolean;
}

export class KargoHelmChart extends Chart {
  constructor(scope: Construct, id: string, props: KargoHelmChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || 'kargo';
    const baseHost = process.env.INGRESS_HOST || 'cnoe.localtest.me';
    const kargoHost = `kargo.${baseHost}`;
    const kargoWebhooksHost = `kargo-webhooks.${baseHost}`;
    const skipGiteaCACerts = props.skipGiteaCACerts ?? false;

    // Create namespace
    new KubeNamespace(this, 'kargo-namespace', {
      metadata: {
        name: namespace,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-20',
        },
        labels: {
          'app.kubernetes.io/name': 'kargo',
          'app.kubernetes.io/managed-by': 'cdk8s',
        },
      },
    });

    // Self-signed certificate valid for 10 years
    // Generated with:
    // openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    //   -keyout tls.key -out tls.crt \
    //   -subj "/CN=kargo-webhooks-server.kargo.svc" \
    //   -addext "subjectAltName=DNS:kargo-webhooks-server,DNS:kargo-webhooks-server.kargo,DNS:kargo-webhooks-server.kargo.svc,DNS:kargo-webhooks-server.kargo.svc.cluster.local"
    const tlsCert = 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR5VENDQXJHZ0F3SUJBZ0lVR1pXU0xqYU5Cbkw1RHBuMFNhaVd5Q1F6aEJVd0RRWUpLb1pJaHZjTkFRRUwKQlFBd0tqRW9NQ1lHQTFVRUF3d2ZhMkZ5WjI4dGQyVmlhRzl2YTNNdGMyVnlkbVZ5TG10aGNtZHZMbk4yWXpBZQpGdzB5TlRBM01qZ3hOekl4TURGYUZ3MHpOVEEzTWpZeE56SXhNREZhTUNveEtEQW1CZ05WQkFNTUgydGhjbWR2CkxYZGxZbWh2YjJ0ekxYTmxjblpsY2k1cllYSm5ieTV6ZG1Nd2dnRWlNQTBHQ1NxR1NJYjNEUUVCQVFVQUE0SUIKRHdBd2dnRUtBb0lCQVFEbitkOVRqTkJBakdDOHN2alRBMWxIOExGRjAyYmw0ZjVIRCsyR2d2Qmk4WkRhcDd2Kwp4bm11cEpUVkhzdEk5L3Zmblc2eWdTU1lWWERpVUoxRUZQbUZiMTYyd2NzcW1idWNWN0N1N0JNUVlDVkFIbzZxCkZxem5TZ2lLU0VpUks2ZzYwdnV4SVF6Y21yaUpWNEhPQkFqSVhlWEJsZWZmL3VvMHNMaE9Jc3JVbFZzMnpCdmMKaHY3eDNoSXR6YWpFSldFTDBaa2l0ZjBsNDJDcmRvNHc2Nmd0eXJaNm93MEo4Ymh4UlZaekc5aTlLbWo2N0FDcgp5aFZnTWtGbmlhY2prUmVlUGF0ejBSM01ZVUk0YXBwRXlncXZ1eGpsQWNmSGJaRkxNVjJaVnlReW53VHl4SzdYClh6MVVuVjF6dVFiZUdUSENYNG5FWksxSzk2dmdOMndHWUMydkFnTUJBQUdqZ2VZd2dlTXdIUVlEVlIwT0JCWUUKRkg5bVpiS2I0RXA0b1gxVmozR1g1OGdNMjEwV01COEdBMVVkSXdRWU1CYUFGSDltWmJLYjRFcDRvWDFWajNHWAo1OGdNMjEwV01BOEdBMVVkRXdFQi93UUZNQU1CQWY4d2dZOEdBMVVkRVFTQmh6Q0JoSUlWYTJGeVoyOHRkMlZpCmFHOXZhM010YzJWeWRtVnlnaHRyWVhKbmJ5MTNaV0pvYjI5cmN5MXpaWEoyWlhJdWEyRnlaMitDSDJ0aGNtZHYKTFhkbFltaHZiMnR6TFhObGNuWmxjaTVyWVhKbmJ5NXpkbU9DTFd0aGNtZHZMWGRsWW1odmIydHpMWE5sY25abApjaTVyWVhKbmJ5NXpkbU11WTJ4MWMzUmxjaTVzYjJOaGJEQU5CZ2txaGtpRzl3MEJBUXNGQUFPQ0FRRUF6ZGJvClVRdVhyUEhUeFd3bVMzZXRRM09QQWFRcHhJb3JkdHhrSTdkVXhhNGJlaFI4ZWlidHJCUkdnaWtHZXZEL2NwWm8KeTJPUm5TQjRrMXBKWEhyUzdidUwzWHp4anRNN3FyQml5UzFGVzZMNFhkeHNnd3NhcGtVenF0VXFkZFIrZ3RuTgoycDh0TXJyZkZBQ1B0RjZwbEdsMTIwYkkxWkVYUGVDOGtqaEs3eGpyQm5wbDdRSUJIWkZjcjlWTmlXVHVMbVMxCmlqSW5Ib21rMWw4bDBuc1lKS0xRdUdpcjRwd1pRVWdTc0RCOUJjSllObjluYkw0emRhUzl5MHlEVFV1M3pVNWIKR0Q0Zi81U1FsaSt3TjhKTnZDL0pTUlhDV1pCMnpQQVdwcjV2ZXhJYy9iRHQ2MzA2d2E5SnU5czd6eTc1OWsrZwpacVExUU5KQVhuYUl2aTdCM2c9PQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg=='
    const tlsKey = 'LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JSUV2d0lCQURBTkJna3Foa2lHOXcwQkFRRUZBQVNDQktrd2dnU2xBZ0VBQW9JQkFRRG4rZDlUak5CQWpHQzgKc3ZqVEExbEg4TEZGMDJibDRmNUhEKzJHZ3ZCaThaRGFwN3YreG5tdXBKVFZIc3RJOS92Zm5XNnlnU1NZVlhEaQpVSjFFRlBtRmIxNjJ3Y3NxbWJ1Y1Y3Q3U3Qk1RWUNWQUhvNnFGcXpuU2dpS1NFaVJLNmc2MHZ1eElRemNtcmlKClY0SE9CQWpJWGVYQmxlZmYvdW8wc0xoT0lzclVsVnMyekJ2Y2h2N3gzaEl0emFqRUpXRUwwWmtpdGYwbDQyQ3IKZG80dzY2Z3R5clo2b3cwSjhiaHhSVlp6RzlpOUttajY3QUNyeWhWZ01rRm5pYWNqa1JlZVBhdHowUjNNWVVJNAphcHBFeWdxdnV4amxBY2ZIYlpGTE1WMlpWeVF5bndUeXhLN1hYejFVblYxenVRYmVHVEhDWDRuRVpLMUs5NnZnCk4yd0dZQzJ2QWdNQkFBRUNnZ0VCQUtFVXZhTUNzTWxoc1ByWFBEa3FwaUJ5WG1haU9WMS81RlhzRlgvR0JLNXcKRjZuOXQybGU0TGdJeU9DRWxaeUJ0b0M4alZXZW40NjRKYjdCUTdNMjdWMWV6R0lUaDhSNUkvR1lZclBVY2hoNAo2dVR2VXhtQXpXZDkzUmhJd1RzdEdaQmZXUzdTU0dBWGYvUytzd0FmaFFtOVNnRjIycUNNSG8yZitSc294YmQrCi9HRFpxL3dYS1gvbmMxR1hTMWZCaGcwbnNWbG9ka1Z2SFhmZThXeWVlTXppbDdwZmJ1bG5pL3kzcm00cGc0a0UKVDNKZStmcjBTWGJ1b0MrUE12RzBNaGRVVzhFNkZ1S3QwYVl0NWMxb1VSdkQwZkFVdWtOOTJFbXhEakFmOHcvRwpocjlQOXF1T25yeU5LUFZHL0FydU9JVE1BL2JmTXNreGJwYWFiZDZJbldFQ2dZRUErZEdCNDVyZkJwTWtwTk9tCjJybkpyKzN4WXBDTG4ycm1ObzVXN21yeFV1UnRPanBHenoyZUFaZTRGNEJSQXFVN3pGL0ZteVJrc2FpRWtoWEIKaVRDTnhKSEZxM3RwM2p4aEh3cnpJV3h0NHJET2ZQQURLcThmRGtONmxYSVlIS2ZWVnZkSTJKdEhYNHp5eFBGSApVUDU5eDd6ZW1MSnRvOVZ3LzZ5dEJLajZrZDBDZ1lFQTdiZFhiR2UyQmxPRFlnRnB6eVg4TlNuRTh5Q3VGNG1YCkdveGtMZFA1Y3BaUzUvdThQNHh1YW03ZnNrSW4wMXRIc1ZaZkpMeHhJZ28ycmQzNFFaWXRMYTBqY2JxcjFSUzEKN08wbzYxWStnZThadHhnc0IvUVo0Y2xtVVNpVmt6QXdEQ1FWY1phS3lwRjd0Mjk1eC9RMHJOdEpySEpkeFFlYQoxZFEzNlJTdU12c0NnWUVBekxLQ3Y4RHk1aXhEWmx1VzZMbzdMTkRIYllBTEtBRXJ5YUF3VXdPRjRlb1NKaGdDClZXV2p4cUpPMGRMdWprQmVFMFNXWWwwYnRRYmtPZDloeWN2akhpSmoyZk14K0V0NU9UcDdwZk4yeHIwaE5QWmwKWWVCRWppZDBsbWY2b2VCVHl3S3N5ZS9TTjlVQ1I2VjhUajE1U3VUVGNFTWoyNDdWSEdxZENxaDdTSEVDZ1lFQQp2ZFZjQzBZSEpxWXFsV2xyaGZGZnAxVGo0d1NHQW1YdU5WVkg2eEVNYzJWNGI2bW9lMWM2RmVUVTN4WFZtQU9kCkRSRmNpWW16RHV2NUhuL1VjUXZzcUQxTHdOYkJ3amYzMEd6VDhKdSs3eVJ4OUxWbzlERUxPalFMY1dSbmpsTTkKQzNVRmF1QTlsZWI0VlZUQWU5Mlk4ekZyZERzZ2h1ZTd6bWJhLzFkMGhXRUNnWUFvMUp6eHF6b1VBWW5GTzVEeQpOZXNLd3FxL05qRHJ4ZFVkamkrRmE5WXd6aWNFY05TQ0JKWHY1Z0d2UkNGck9ldVVXcGQ4Wk0vMVZCWGc1aWJqCm1vN1drTVRwZ0luTHorNHdoTkJkVXB1QnlQWUVPdlZuMXFpS3hIWlJYZTJmMWFvUnhHb05pU2RmQUcwZXI2YXYKemZkYnNDRWRwRHNyWjN6QWJlSTZQT0lkcEE9PQotLS0tLUVORCBQUklWQVRFIEtFWS0tLS0tCg=='

    // Create the webhook server certificate secret
    new KubeSecret(this, 'kargo-webhooks-server-cert', {
      metadata: {
        name: 'kargo-webhooks-server-cert',
        namespace: namespace,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-15', // Deploy before Helm chart
        },
      },
      type: 'kubernetes.io/tls',
      data: {
        'tls.crt': tlsCert,
        'tls.key': tlsKey,
      },
    });

    // Deploy Kargo using Helm chart directly
    const kargoHelm = new Helm(this, 'kargo', {
      chart: 'oci://ghcr.io/akuity/kargo-charts/kargo',
      version: '1.8.4',
      namespace: namespace,
      releaseName: 'kargo',
      values: {
        api: {
          // IMPORTANT: Set the host to avoid conflict with other services
          host: kargoHost,
          // Admin account configuration - hardcoded for now, should use External Secrets
          adminAccount: {
            passwordHash: '$2y$10$wvzqHozwu7ms8FdT7m2Q7eF0YWsLfJX491neGKwuiztq2hFDvGgPW',
            tokenSigningKey: 'pw4J0w4L2sMcvsbdWNPgWSeOuBm1IK0b',
            tokenTTL: '24h',
          },
          // Service configuration
          service: {
            type: 'ClusterIP',
            port: 8080,
          },
          // Enable gRPC web support for UI
          grpcWeb: true,
          // Logging
          logLevel: 'INFO',
          // TLS configuration - disable TLS and rely on ingress
          tls: {
            enabled: false,
          },
          // Ingress configuration
          ingress: {
            enabled: true,
            className: 'nginx',
            annotations: {
              'nginx.ingress.kubernetes.io/backend-protocol': 'HTTP',
              'nginx.ingress.kubernetes.io/grpc-backend': 'true',
            },
            tls: {
              enabled: false, // nginx already handles TLS termination
            },
          },
          // Resources
          resources: {
            requests: {
              cpu: '100m',
              memory: '128Mi',
            },
            limits: {
              cpu: '500m',
              memory: '256Mi',
            },
          },
        },
        // Controller configuration
        controller: {
          logLevel: 'INFO',
          resources: {
            requests: {
              cpu: '100m',
              memory: '128Mi',
            },
            limits: {
              cpu: '500m',
              memory: '512Mi',
            },
          },
          // Mount CA certificates for self-signed certificate trust (KIND/Gitea only)
          // Talos clusters use GitHub with valid SSL certs, so this is skipped
          ...(skipGiteaCACerts ? {} : {
            volumes: [
              {
                name: 'ca-certificates',
                configMap: {
                  name: 'gitea-ca-cert',
                  items: [
                    {
                      key: 'ca.crt',
                      path: 'gitea-ca.crt'
                    }
                  ]
                }
              }
            ],
            volumeMounts: [
              {
                name: 'ca-certificates',
                mountPath: '/etc/ssl/certs/gitea-ca.crt',
                subPath: 'gitea-ca.crt',
                readOnly: true
              }
            ],
            env: [
              {
                name: 'SSL_CERT_FILE',
                value: '/etc/ssl/certs/gitea-ca.crt'
              },
              {
                name: 'SSL_CERT_DIR',
                value: '/etc/ssl/certs'
              }
            ],
          }),
        },
        // Webhooks configuration - enable with custom certificates
        webhooksServer: {
          enabled: true,
          tls: {
            selfSignedCert: false,  // We provide our own certificate
          },
        },
        webhooks: {
          register: true,  // Enable webhook registration now that we have certificates
          logLevel: 'INFO',
          resources: {
            requests: {
              cpu: '100m',
              memory: '128Mi',
            },
            limits: {
              cpu: '200m',
              memory: '256Mi',
            },
          },
        },
        // Management controller configuration
        management: {
          logLevel: 'INFO',
          resources: {
            requests: {
              cpu: '50m',
              memory: '64Mi',
            },
            limits: {
              cpu: '100m',
              memory: '128Mi',
            },
          },
        },
        // Garbage collector configuration
        garbageCollector: {
          resources: {
            requests: {
              cpu: '50m',
              memory: '64Mi',
            },
            limits: {
              cpu: '100m',
              memory: '128Mi',
            },
          },
        },
        // External webhooks configuration
        externalWebhooksServer: {
          enabled: true,
          tls: {
            enabled: false,
          },
        },
        // Disable AWS-specific features for local development
        awsLoadBalancerController: {
          enabled: false,
        },
        // RBAC configuration
        rbac: {
          installClusterRoles: true,
          installClusterRoleBindings: true,
        },
        // Disable cert-manager certificate generation (not needed when TLS is disabled)
        certificates: {
          enabled: false,
        },
        // Additional annotations for all resources
        global: {
          annotations: {
            'app.kubernetes.io/managed-by': 'cdk8s',
          },
        },
      },
    });

    // Create Ingress for external webhooks server (typed)
    new KubeIngress(this, 'kargo-external-webhooks-ingress', {
      metadata: {
        name: 'kargo-external-webhooks',
        namespace: namespace,
        annotations: {
          'nginx.ingress.kubernetes.io/backend-protocol': 'HTTP',
          'nginx.ingress.kubernetes.io/force-ssl-redirect': 'true',
          'nginx.ingress.kubernetes.io/ssl-protocols': 'TLSv1.2 TLSv1.3',
          'cert-manager.io/cluster-issuer': 'letsencrypt-cloudflare',
        },
        labels: {
          'app.kubernetes.io/name': 'kargo-external-webhooks',
          'app.kubernetes.io/part-of': 'kargo',
          'app.kubernetes.io/managed-by': 'cdk8s'
        }
      },
      spec: {
        ingressClassName: 'nginx',
        tls: [
          {
            hosts: [kargoWebhooksHost],
            secretName: 'kargo-webhooks-tls'
          }
        ],
        rules: [
          {
            host: kargoWebhooksHost,
            http: {
              paths: [
                {
                  path: '/',
                  pathType: 'Prefix',
                  backend: {
                    service: {
                      name: 'kargo-external-webhooks-server',
                      port: { number: 80 }
                    }
                  }
                }
              ]
            }
          }
        ]
      }
    });

    // Fix the kargo-api Ingress to add ingressClassName and TLS configuration
    // The Helm chart doesn't properly set these fields
    const kargoApiIngress = kargoHelm.apiObjects.find(obj =>
      obj.kind === 'Ingress' && obj.name === 'kargo-api'
    );

    if (kargoApiIngress) {
      // Add ingressClassName to spec
      kargoApiIngress.addJsonPatch(JsonPatch.add('/spec/ingressClassName', 'nginx'));

      // Add cert-manager annotation for automatic TLS certificate
      // Uses letsencrypt-cloudflare (DNS-01 challenge) for Talos clusters
      kargoApiIngress.addJsonPatch(JsonPatch.add('/metadata/annotations/cert-manager.io~1cluster-issuer', 'letsencrypt-cloudflare'));

      // Add TLS configuration for HTTPS termination
      kargoApiIngress.addJsonPatch(JsonPatch.add('/spec/tls', [
        {
          hosts: [kargoHost],
          secretName: 'kargo-api-tls'
        }
      ]));
    }

    // Fix webhook configurations by removing cert-manager annotations and adding CA bundle
    // Find the ValidatingWebhookConfiguration
    const validatingWebhook = kargoHelm.apiObjects.find(obj =>
      obj.kind === 'ValidatingWebhookConfiguration' && obj.name === 'kargo'
    );
    
    // Find the MutatingWebhookConfiguration
    const mutatingWebhook = kargoHelm.apiObjects.find(obj => 
      obj.kind === 'MutatingWebhookConfiguration' && obj.name === 'kargo'
    );
    
    // Fix ValidatingWebhookConfiguration
    if (validatingWebhook) {
      // Remove cert-manager annotation
      validatingWebhook.addJsonPatch(JsonPatch.remove('/metadata/annotations/cert-manager.io~1inject-ca-from'));
      
      // Add CA bundle to each webhook (there are 9 webhooks in the validating configuration)
      for (let i = 0; i < 9; i++) {
        validatingWebhook.addJsonPatch(JsonPatch.add(
          `/webhooks/${i}/clientConfig/caBundle`,
          tlsCert  // Use the same cert we created for the secret
        ));
      }
    }
    
    // Fix MutatingWebhookConfiguration
    if (mutatingWebhook) {
      // Remove cert-manager annotation
      mutatingWebhook.addJsonPatch(JsonPatch.remove('/metadata/annotations/cert-manager.io~1inject-ca-from'));
      
      // Add CA bundle to each webhook (there are 4 webhooks in the mutating configuration)
      for (let i = 0; i < 4; i++) {
        mutatingWebhook.addJsonPatch(JsonPatch.add(
          `/webhooks/${i}/clientConfig/caBundle`,
          tlsCert  // Use the same cert we created for the secret
        ));
      }
    }

    // PostSync hook job is no longer needed since we're fixing the webhooks at synthesis time
    // The CA bundle is now added directly to the webhook configurations via JsonPatch
  }
}
