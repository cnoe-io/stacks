import { Chart, ChartProps, Helm, JsonPatch } from 'cdk8s';
import { Construct } from 'constructs';
import { KubeNamespace, KubeSecret, KubeClusterRole, KubeClusterRoleBinding } from '../../imports/k8s';

export interface KargoHubHelmChartProps extends ChartProps {
  namespace?: string;
  /**
   * Kargo admin password hash (bcrypt).
   * Generate with: htpasswd -nbBC 10 "" "yourpassword" | tr -d ':\n'
   */
  adminPasswordHash?: string;
  /**
   * Token signing key for Kargo API.
   */
  tokenSigningKey?: string;
}

/**
 * Hub-specific Kargo Helm chart deployment.
 *
 * Key differences from KIND deployment:
 * - No Gitea CA certificates (uses GitHub/GHCR with valid SSL)
 * - No nginx ingress (exposed via Tailscale Serve instead)
 * - Cross-cluster RBAC for managing spoke ArgoCD applications
 */
export class KargoHubHelmChart extends Chart {
  constructor(scope: Construct, id: string, props: KargoHubHelmChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || 'kargo';

    // Hub doesn't use nginx ingress - Kargo UI is exposed via Tailscale Serve
    // API is accessed internally via kargo-api.kargo.svc.cluster.local

    // Default admin credentials (should be sourced from Azure Key Vault in production)
    const adminPasswordHash = props.adminPasswordHash ||
      '$2b$10$bqVe5nszNR1eEt20jtNSle24cBsnhiiNcFHgZuMcv7HACZCD6a3IW'; // KargoAdmin2025
    const tokenSigningKey = props.tokenSigningKey ||
      'pw4J0w4L2sMcvsbdWNPgWSeOuBm1IK0b';

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

    // Self-signed certificate for webhook server
    const tlsCert = 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR5VENDQXJHZ0F3SUJBZ0lVR1pXU0xqYU5Cbkw1RHBuMFNhaVd5Q1F6aEJVd0RRWUpLb1pJaHZjTkFRRUwKQlFBd0tqRW9NQ1lHQTFVRUF3d2ZhMkZ5WjI4dGQyVmlhRzl2YTNNdGMyVnlkbVZ5TG10aGNtZHZMbk4yWXpBZQpGdzB5TlRBM01qZ3hOekl4TURGYUZ3MHpOVEEzTWpZeE56SXhNREZhTUNveEtEQW1CZ05WQkFNTUgydGhjbWR2CkxYZGxZbWh2YjJ0ekxYTmxjblpsY2k1cllYSm5ieTV6ZG1Nd2dnRWlNQTBHQ1NxR1NJYjNEUUVCQVFVQUE0SUIKRHdBd2dnRUtBb0lCQVFEbitkOVRqTkJBakdDOHN2alRBMWxIOExGRjAyYmw0ZjVIRCsyR2d2Qmk4WkRhcDd2Kwp4bm11cEpUVkhzdEk5L3Zmblc2eWdTU1lWWERpVUoxRUZQbUZiMTYyd2NzcW1idWNWN0N1N0JNUVlDVkFIbzZxCkZxem5TZ2lLU0VpUks2ZzYwdnV4SVF6Y21yaUpWNEhPQkFqSVhlWEJsZWZmL3VvMHNMaE9Jc3JVbFZzMnpCdmMKaHY3eDNoSXR6YWpFSldFTDBaa2l0ZjBsNDJDcmRvNHc2Nmd0eXJaNm93MEo4Ymh4UlZaekc5aTlLbWo2N0FDcgp5aFZnTWtGbmlhY2prUmVlUGF0ejBSM01ZVUk0YXBwRXlncXZ1eGpsQWNmSGJaRkxNVjJaVnlReW53VHl4SzdYClh6MVVuVjF6dVFiZUdUSENYNG5FWksxSzk2dmdOMndHWUMydkFnTUJBQUdqZ2VZd2dlTXdIUVlEVlIwT0JCWUUKRkg5bVpiS2I0RXA0b1gxVmozR1g1OGdNMjEwV01COEdBMVVkSXdRWU1CYUFGSDltWmJLYjRFcDRvWDFWajNHWAo1OGdNMjEwV01BOEdBMVVkRXdFQi93UUZNQU1CQWY4d2dZOEdBMVVkRVFTQmh6Q0JoSUlWYTJGeVoyOHRkMlZpCmFHOXZhM010YzJWeWRtVnlnaHRyWVhKbmJ5MTNaV0pvYjI5cmN5MXpaWEoyWlhJdWEyRnlaMitDSDJ0aGNtZHYKTFhkbFltaHZiMnR6TFhObGNuWmxjaTVyWVhKbmJ5NXpkbU9DTFd0aGNtZHZMWGRsWW1odmIydHpMWE5sY25abApjaTVyWVhKbmJ5NXpkbU11WTJ4MWMzUmxjaTVzYjJOaGJEQU5CZ2txaGtpRzl3MEJBUXNGQUFPQ0FRRUF6ZGJvClVRdVhyUEhUeFd3bVMzZXRRM09QQWFRcHhJb3JkdHhrSTdkVXhhNGJlaFI4ZWlidHJCUkdnaWtHZXZEL2NwWm8KeTJPUm5TQjRrMXBKWEhyUzdidUwzWHp4anRNN3FyQml5UzFGVzZMNFhkeHNnd3NhcGtVenF0VXFkZFIrZ3RuTgoycDh0TXJyZkZBQ1B0RjZwbEdsMTIwYkkxWkVYUGVDOGtqaEs3eGpyQm5wbDdRSUJIWkZjcjlWTmlXVHVMbVMxCmlqSW5Ib21rMWw4bDBuc1lKS0xRdUdpcjRwd1pRVWdTc0RCOUJjSllObjluYkw0emRhUzl5MHlEVFV1M3pVNWIKR0Q0Zi81U1FsaSt3TjhKTnZDL0pTUlhDV1pCMnpQQVdwcjV2ZXhJYy9iRHQ2MzA2d2E5SnU5czd6eTc1OWsrZwpacVExUU5KQVhuYUl2aTdCM2c9PQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg==';
    const tlsKey = 'LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JSUV2d0lCQURBTkJna3Foa2lHOXcwQkFRRUZBQVNDQktrd2dnU2xBZ0VBQW9JQkFRRG4rZDlUak5CQWpHQzgKc3ZqVEExbEg4TEZGMDJibDRmNUhEKzJHZ3ZCaThaRGFwN3YreG5tdXBKVFZIc3RJOS92Zm5XNnlnU1NZVlhEaQpVSjFFRlBtRmIxNjJ3Y3NxbWJ1Y1Y3Q3U3Qk1RWUNWQUhvNnFGcXpuU2dpS1NFaVJLNmc2MHZ1eElRemNtcmlKClY0SE9CQWpJWGVYQmxlZmYvdW8wc0xoT0lzclVsVnMyekJ2Y2h2N3gzaEl0emFqRUpXRUwwWmtpdGYwbDQyQ3IKZG80dzY2Z3R5clo2b3cwSjhiaHhSVlp6RzlpOUttajY3QUNyeWhWZ01rRm5pYWNqa1JlZVBhdHowUjNNWVVJNAphcHBFeWdxdnV4amxBY2ZIYlpGTE1WMlpWeVF5bndUeXhLN1hYejFVblYxenVRYmVHVEhDWDRuRVpLMUs5NnZnCk4yd0dZQzJ2QWdNQkFBRUNnZ0VCQUtFVXZhTUNzTWxoc1ByWFBEa3FwaUJ5WG1haU9WMS81RlhzRlgvR0JLNXcKRjZuOXQybGU0TGdJeU9DRWxaeUJ0b0M4alZXZW40NjRKYjdCUTdNMjdWMWV6R0lUaDhSNUkvR1lZclBVY2hoNAo2dVR2VXhtQXpXZDkzUmhJd1RzdEdaQmZXUzdTU0dBWGYvUytzd0FmaFFtOVNnRjIycUNNSG8yZitSc294YmQrCi9HRFpxL3dYS1gvbmMxR1hTMWZCaGcwbnNWbG9ka1Z2SFhmZThXeWVlTXppbDdwZmJ1bG5pL3kzcm00cGc0a0UKVDNKZStmcjBTWGJ1b0MrUE12RzBNaGRVVzhFNkZ1S3QwYVl0NWMxb1VSdkQwZkFVdWtOOTJFbXhEakFmOHcvRwpocjlQOXF1T25yeU5LUFZHL0FydU9JVE1BL2JmTXNreGJwYWFiZDZJbldFQ2dZRUErZEdCNDVyZkJwTWtwTk9tCjJybkpyKzN4WXBDTG4ycm1ObzVXN21yeFV1UnRPanBHenoyZUFaZTRGNEJSQXFVN3pGL0ZteVJrc2FpRWtoWEIKaVRDTnhKSEZxM3RwM2p4aEh3cnpJV3h0NHJET2ZQQURLcThmRGtONmxYSVlIS2ZWVnZkSTJKdEhYNHp5eFBGSApVUDU5eDd6ZW1MSnRvOVZ3LzZ5dEJLajZrZDBDZ1lFQTdiZFhiR2UyQmxPRFlnRnB6eVg4TlNuRTh5Q3VGNG1YCkdveGtMZFA1Y3BaUzUvdThQNHh1YW03ZnNrSW4wMXRIc1ZaZkpMeHhJZ28ycmQzNFFaWXRMYTBqY2JxcjFSUzEKN08wbzYxWStnZThadHhnc0IvUVo0Y2xtVVNpVmt6QXdEQ1FWY1phS3lwRjd0Mjk1eC9RMHJOdEpySEpkeFFlYQoxZFEzNlJTdU12c0NnWUVBekxLQ3Y4RHk1aXhEWmx1VzZMbzdMTkRIYllBTEtBRXJ5YUF3VXdPRjRlb1NKaGdDClZXV2p4cUpPMGRMdWprQmVFMFNXWWwwYnRRYmtPZDloeWN2akhpSmoyZk14K0V0NU9UcDdwZk4yeHIwaE5QWmwKWWVCRWppZDBsbWY2b2VCVHl3S3N5ZS9TTjlVQ1I2VjhUajE1U3VUVGNFTWoyNDdWSEdxZENxaDdTSEVDZ1lFQQp2ZFZjQzBZSEpxWXFsV2xyaGZGZnAxVGo0d1NHQW1YdU5WVkg2eEVNYzJWNGI2bW9lMWM2RmVUVTN4WFZtQU9kCkRSRmNpWW16RHV2NUhuL1VjUXZzcUQxTHdOYkJ3amYzMEd6VDhKdSs3eVJ4OUxWbzlERUxPalFMY1dSbmpsTTkKQzNVRmF1QTlsZWI0VlZUQWU5Mlk4ekZyZERzZ2h1ZTd6bWJhLzFkMGhXRUNnWUFvMUp6eHF6b1VBWW5GTzVEeQpOZXNLd3FxL05qRHJ4ZFVkamkrRmE5WXd6aWNFY05TQ0JKWHY1Z0d2UkNGck9ldVVXcGQ4Wk0vMVZCWGc1aWJqCm1vN1drTVRwZ0luTHorNHdoTkJkVXB1QnlQWUVPdlZuMXFpS3hIWlJYZTJmMWFvUnhHb05pU2RmQUcwZXI2YXYKemZkYnNDRWRwRHNyWjN6QWJlSTZQT0lkcEE9PQotLS0tLUVORCBQUklWQVRFIEtFWS0tLS0tCg==';

    // Create the webhook server certificate secret
    new KubeSecret(this, 'kargo-webhooks-server-cert', {
      metadata: {
        name: 'kargo-webhooks-server-cert',
        namespace: namespace,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-15',
        },
      },
      type: 'kubernetes.io/tls',
      data: {
        'tls.crt': tlsCert,
        'tls.key': tlsKey,
      },
    });

    // Deploy Kargo using Helm chart
    const kargoHelm = new Helm(this, 'kargo', {
      chart: 'oci://ghcr.io/akuity/kargo-charts/kargo',
      version: '1.8.4',
      namespace: namespace,
      releaseName: 'kargo',
      values: {
        api: {
          // No host needed - exposed via Tailscale Serve
          host: '',
          adminAccount: {
            passwordHash: adminPasswordHash,
            tokenSigningKey: tokenSigningKey,
            tokenTTL: '24h',
          },
          service: {
            type: 'ClusterIP',
            port: 8080,
          },
          grpcWeb: true,
          logLevel: 'INFO',
          tls: {
            enabled: false,
          },
          // Disable ingress - using Tailscale Serve instead
          ingress: {
            enabled: false,
          },
          resources: {
            requests: { cpu: '100m', memory: '128Mi' },
            limits: { cpu: '500m', memory: '256Mi' },
          },
        },
        controller: {
          logLevel: 'INFO',
          resources: {
            requests: { cpu: '100m', memory: '128Mi' },
            limits: { cpu: '500m', memory: '512Mi' },
          },
          // No Gitea CA certs needed - hub uses GitHub/GHCR with valid SSL
        },
        webhooksServer: {
          enabled: true,
          tls: {
            selfSignedCert: false,
          },
        },
        webhooks: {
          register: true,
          logLevel: 'INFO',
          resources: {
            requests: { cpu: '100m', memory: '128Mi' },
            limits: { cpu: '200m', memory: '256Mi' },
          },
        },
        management: {
          logLevel: 'INFO',
          resources: {
            requests: { cpu: '50m', memory: '64Mi' },
            limits: { cpu: '100m', memory: '128Mi' },
          },
        },
        garbageCollector: {
          resources: {
            requests: { cpu: '50m', memory: '64Mi' },
            limits: { cpu: '100m', memory: '128Mi' },
          },
        },
        externalWebhooksServer: {
          enabled: true,
          tls: { enabled: false },
        },
        awsLoadBalancerController: { enabled: false },
        rbac: {
          installClusterRoles: true,
          installClusterRoleBindings: true,
        },
        certificates: { enabled: false },
        global: {
          annotations: {
            'app.kubernetes.io/managed-by': 'cdk8s',
          },
        },
      },
    });

    // Fix webhook configurations
    const validatingWebhook = kargoHelm.apiObjects.find(obj =>
      obj.kind === 'ValidatingWebhookConfiguration' && obj.name === 'kargo'
    );
    const mutatingWebhook = kargoHelm.apiObjects.find(obj =>
      obj.kind === 'MutatingWebhookConfiguration' && obj.name === 'kargo'
    );

    if (validatingWebhook) {
      validatingWebhook.addJsonPatch(JsonPatch.remove('/metadata/annotations/cert-manager.io~1inject-ca-from'));
      for (let i = 0; i < 9; i++) {
        validatingWebhook.addJsonPatch(JsonPatch.add(`/webhooks/${i}/clientConfig/caBundle`, tlsCert));
      }
    }

    if (mutatingWebhook) {
      mutatingWebhook.addJsonPatch(JsonPatch.remove('/metadata/annotations/cert-manager.io~1inject-ca-from'));
      for (let i = 0; i < 4; i++) {
        mutatingWebhook.addJsonPatch(JsonPatch.add(`/webhooks/${i}/clientConfig/caBundle`, tlsCert));
      }
    }

    // Create ClusterRole for managing spoke ArgoCD applications
    // This allows Kargo controller to update ArgoCD Applications targeting spoke clusters
    new KubeClusterRole(this, 'kargo-argocd-spoke-manager', {
      metadata: {
        name: 'kargo-argocd-spoke-manager',
        annotations: {
          'argocd.argoproj.io/sync-wave': '-10',
        },
        labels: {
          'app.kubernetes.io/name': 'kargo',
          'app.kubernetes.io/component': 'spoke-manager',
        },
      },
      rules: [
        {
          apiGroups: ['argoproj.io'],
          resources: ['applications'],
          verbs: ['get', 'list', 'watch', 'update', 'patch'],
        },
        {
          apiGroups: ['argoproj.io'],
          resources: ['applications/status'],
          verbs: ['get', 'list', 'watch'],
        },
      ],
    });

    // Bind the ClusterRole to Kargo controller ServiceAccount
    new KubeClusterRoleBinding(this, 'kargo-argocd-spoke-manager-binding', {
      metadata: {
        name: 'kargo-argocd-spoke-manager',
        annotations: {
          'argocd.argoproj.io/sync-wave': '-5',
        },
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: 'kargo-argocd-spoke-manager',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: 'kargo-controller',
          namespace: namespace,
        },
        {
          kind: 'ServiceAccount',
          name: 'kargo-api',
          namespace: namespace,
        },
      ],
    });
  }
}
