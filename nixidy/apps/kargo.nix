# Kargo - Progressive Delivery
# Provides GitOps-based progressive delivery for Kubernetes.
#
# NOTE: Kargo uses OCI registry (ghcr.io/akuity/kargo-charts) which nixidy doesn't support.
# We use ArgoCD Application with OCI Helm source - ArgoCD handles OCI natively.
# See: https://nixidy.dev/user_guide/helm_charts/
#
# Mirrors: cdk8s/config/applications.ts kargo entries
{ config, lib, ... }:
let
  namespace = "kargo";
in
{
  config = {
    # Kargo Secrets
    applications.kargo-secrets = lib.mkIf (config.environmentType == "talos") {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "60";
      };

      syncPolicy = {
        autoSync = {
          enable = true;
          prune = true;
          selfHeal = true;
        };
        syncOptions = {
          createNamespace = true;
          serverSideApply = true;
        };
        retry = {
          limit = 5;
          backoff = {
            duration = "5s";
            factor = 2;
            maxDuration = "3m";
          };
        };
      };

      yamls = [
        ''
          apiVersion: external-secrets.io/v1
          kind: ExternalSecret
          metadata:
            name: kargo-admin-credentials
            namespace: ${namespace}
          spec:
            refreshInterval: 1h
            secretStoreRef:
              kind: ClusterSecretStore
              name: azure-keyvault-store
            target:
              name: kargo-admin-credentials
              creationPolicy: Owner
            data:
              - secretKey: ADMIN_ACCOUNT_PASSWORD
                remoteRef:
                  key: kargo-admin-password
        ''
      ];
    };

    # Kargo webhooks certificate secret (since we disable cert-manager)
    applications.kargo-webhooks-cert = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "60";  # Deploy before kargo-helm
      };

      syncPolicy = {
        autoSync = {
          enable = true;
          prune = true;
          selfHeal = true;
        };
        syncOptions = {
          createNamespace = true;
        };
      };

      yamls = [
        ''
          apiVersion: v1
          kind: Secret
          metadata:
            name: kargo-webhooks-server-cert
            namespace: ${namespace}
          type: kubernetes.io/tls
          data:
            tls.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR5VENDQXJHZ0F3SUJBZ0lVR1pXU0xqYU5Cbkw1RHBuMFNhaVd5Q1F6aEJVd0RRWUpLb1pJaHZjTkFRRUwKQlFBd0tqRW9NQ1lHQTFVRUF3d2ZhMkZ5WjI4dGQyVmlhRzl2YTNNdGMyVnlkbVZ5TG10aGNtZHZMbk4yWXpBZQpGdzB5TlRBM01qZ3hOekl4TURGYUZ3MHpOVEEzTWpZeE56SXhNREZhTUNveEtEQW1CZ05WQkFNTUgydGhjbWR2CkxYZGxZbWh2YjJ0ekxYTmxjblpsY2k1cllYSm5ieTV6ZG1Nd2dnRWlNQTBHQ1NxR1NJYjNEUUVCQVFVQUE0SUIKRHdBd2dnRUtBb0lCQVFEbitkOVRqTkJBakdDOHN2alRBMWxIOExGRjAyYmw0ZjVIRCsyR2d2Qmk4WkRhcDd2Kwp4bm11cEpUVkhzdEk5L3Zmblc2eWdTU1lWWERpVUoxRUZQbUZiMTYyd2NzcW1idWNWN0N1N0JNUVlDVkFIbzZxCkZxem5TZ2lLU0VpUks2ZzYwdnV4SVF6Y21yaUpWNEhPQkFqSVhlWEJsZWZmL3VvMHNMaE9Jc3JVbFZzMnpCdmMKaHY3eDNoSXR6YWpFSldFTDBaa2l0ZjBsNDJDcmRvNHc2Nmd0eXJaNm93MEo4Ymh4UlZaekc5aTlLbWo2N0FDcgp5aFZnTWtGbmlhY2prUmVlUGF0ejBSM01ZVUk0YXBwRXlncXZ1eGpsQWNmSGJaRkxNVjJaVnlReW53VHl4SzdYClh6MVVuVjF6dVFiZUdUSENYNG5FWksxSzk2dmdOMndHWUMydkFnTUJBQUdqZ2VZd2dlTXdIUVlEVlIwT0JCWUUKRkg5bVpiS2I0RXA0b1gxVmozR1g1OGdNMjEwV01COEdBMVVkSXdRWU1CYUFGSDltWmJLYjRFcDRvWDFWajNHWAo1OGdNMjEwV01BOEdBMVVkRXdFQi93UUZNQU1CQWY4d2dZOEdBMVVkRVFTQmh6Q0JoSUlWYTJGeVoyOHRkMlZpCmFHOXZhM010YzJWeWRtVnlnaHRyWVhKbmJ5MTNaV0pvYjI5cmN5MXpaWEoyWlhJdWEyRnlaMitDSDJ0aGNtZHYKTFhkbFltaHZiMnR6TFhObGNuWmxjaTVyWVhKbmJ5NXpkbU9DTFd0aGNtZHZMWGRsWW1odmIydHpMWE5sY25abApjaTVyWVhKbmJ5NXpkbU11WTJ4MWMzUmxjaTVzYjJOaGJEQU5CZ2txaGtpRzl3MEJBUXNGQUFPQ0FRRUF6ZGJvClVRdVhyUEhUeFd3bVMzZXRRM09QQWFRcHhJb3JkdHhrSTdkVXhhNGJlaFI4ZWlidHJCUkdnaWtHZXZEL2NwWm8KeTJPUm5TQjRrMXBKWEhyUzdidUwzWHp4anRNN3FyQml5UzFGVzZMNFhkeHNnd3NhcGtVenF0VXFkZFIrZ3RuTgoycDh0TXJyZkZBQ1B0RjZwbEdsMTIwYkkxWkVYUGVDOGtqaEs3eGpyQm5wbDdRSUJIWkZjcjlWTmlXVHVMbVMxCmlqSW5Ib21rMWw4bDBuc1lKS0xRdUdpcjRwd1pRVWdTc0RCOUJjSllObjluYkw0emRhUzl5MHlEVFV1M3pVNWIKR0Q0Zi81U1FsaSt3TjhKTnZDL0pTUlhDV1pCMnpQQVdwcjV2ZXhJYy9iRHQ2MzA2d2E5SnU5czd6eTc1OWsrZwpacVExUU5KQVhuYUl2aTdCM2c9PQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg==
            tls.key: LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JSUV2d0lCQURBTkJna3Foa2lHOXcwQkFRRUZBQVNDQktrd2dnU2xBZ0VBQW9JQkFRRG4rZDlUak5CQWpHQzgKc3ZqVEExbEg4TEZGMDJibDRmNUhEKzJHZ3ZCaThaRGFwN3YreG5tdXBKVFZIc3RJOS92Zm5XNnlnU1NZVlhEaQpVSjFFRlBtRmIxNjJ3Y3NxbWJ1Y1Y3Q3U3Qk1RWUNWQUhvNnFGcXpuU2dpS1NFaVJLNmc2MHZ1eElRemNtcmlKClY0SE9CQWpJWGVYQmxlZmYvdW8wc0xoT0lzclVsVnMyekJ2Y2h2N3gzaEl0emFqRUpXRUwwWmtpdGYwbDQyQ3IKZG80dzY2Z3R5clo2b3cwSjhiaHhSVlp6RzlpOUttajY3QUNyeWhWZ01rRm5pYWNqa1JlZVBhdHowUjNNWVVJNAphcHBFeWdxdnV4amxBY2ZIYlpGTE1WMlpWeVF5bndUeXhLN1hYejFVblYxenVRYmVHVEhDWDRuRVpLMUs5NnZnCk4yd0dZQzJ2QWdNQkFBRUNnZ0VCQUtFVXZhTUNzTWxoc1ByWFBEa3FwaUJ5WG1haU9WMS81RlhzRlgvR0JLNXcKRjZuOXQybGU0TGdJeU9DRWxaeUJ0b0M4alZXZW40NjRKYjdCUTdNMjdWMWV6R0lUaDhSNUkvR1lZclBVY2hoNAo2dVR2VXhtQXpXZDkzUmhJd1RzdEdaQmZXUzdTU0dBWGYvUytzd0FmaFFtOVNnRjIycUNNSG8yZitSc294YmQrCi9HRFpxL3dYS1gvbmMxR1hTMWZCaGcwbnNWbG9ka1Z2SFhmZThXeWVlTXppbDdwZmJ1bG5pL3kzcm00cGc0a0UKVDNKZStmcjBTWGJ1b0MrUE12RzBNaGRVVzhFNkZ1S3QwYVl0NWMxb1VSdkQwZkFVdWtOOTJFbXhEakFmOHcvRwpocjlQOXF1T25yeU5LUFZHL0FydU9JVE1BL2JmTXNreGJwYWFiZDZJbldFQ2dZRUErZEdCNDVyZkJwTWtwTk9tCjJybkpyKzN4WXBDTG4ycm1ObzVXN21yeFV1UnRPanBHenoyZUFaZTRGNEJSQXFVN3pGL0ZteVJrc2FpRWtoWEIKaVRDTnhKSEZxM3RwM2p4aEh3cnpJV3h0NHJET2ZQQURLcThmRGtONmxYSVlIS2ZWVnZkSTJKdEhYNHp5eFBGSApVUDU5eDd6ZW1MSnRvOVZ3LzZ5dEJLajZrZDBDZ1lFQTdiZFhiR2UyQmxPRFlnRnB6eVg4TlNuRTh5Q3VGNG1YCkdveGtMZFA1Y3BaUzUvdThQNHh1YW03ZnNrSW4wMXRIc1ZaZkpMeHhJZ28ycmQzNFFaWXRMYTBqY2JxcjFSUzEKN08wbzYxWStnZThadHhnc0IvUVo0Y2xtVVNpVmt6QXdEQ1FWY1phS3lwRjd0Mjk1eC9RMHJOdEpySEpkeFFlYQoxZFEzNlJTdU12c0NnWUVBekxLQ3Y4RHk1aXhEWmx1VzZMbzdMTkRIYllBTEtBRXJ5YUF3VXdPRjRlb1NKaGdDClZXV2p4cUpPMGRMdWprQmVFMFNXWWwwYnRRYmtPZDloeWN2akhpSmoyZk14K0V0NU9UcDdwZk4yeHIwaE5QWmwKWWVCRWppZDBsbWY2b2VCVHl3S3N5ZS9TTjlVQ1I2VjhUajE1U3VUVGNFTWoyNDdWSEdxZENxaDdTSEVDZ1lFQQp2ZFZjQzBZSEpxWXFsV2xyaGZGZnAxVGo0d1NHQW1YdU5WVkg2eEVNYzJWNGI2bW9lMWM2RmVUVTN4WFZtQU9kCkRSRmNpWW16RHV2NUhuL1VjUXZzcUQxTHdOYkJ3amYzMEd6VDhKdSs3eVJ4OUxWbzlERUxPalFMY1dSbmpsTTkKQzNVRmF1QTlsZWI0VlZUQWU5Mlk4ekZyZERzZ2h1ZTd6bWJhLzFkMGhXRUNnWUFvMUp6eHF6b1VBWW5GTzVEeQpOZXNLd3FxL05qRHJ4ZFVkamkrRmE5WXd6aWNFY05TQ0JKWHY1Z0d2UkNGck9ldVVXcGQ4Wk0vMVZCWGc1aWJqCm1vN1drTVRwZ0luTHorNHdoTkJkVXB1QnlQWUVPdlZuMXFpS3hIWlJYZTJmMWFvUnhHb05pU2RmQUcwZXI2YXYKemZkYnNDRWRwRHNyWjN6QWJlSTZQT0lkcEE9PQotLS0tLUVORCBQUklWQVRFIEtFWS0tLS0tCg==
        ''
      ];
    };

    # Kargo application - via ArgoCD OCI Helm Application
    applications.kargo = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "65";
      };

      syncPolicy = {
        autoSync = {
          enable = true;
          prune = true;
          selfHeal = true;
        };
        syncOptions = {
          createNamespace = true;
          serverSideApply = true;
        };
      };

      # Use ArgoCD Application with OCI Helm source (nixidy doesn't support OCI)
      yamls = [
        ''
          apiVersion: argoproj.io/v1alpha1
          kind: Application
          metadata:
            name: kargo-helm
            namespace: argocd
            annotations:
              argocd.argoproj.io/sync-wave: "65"
          spec:
            project: default
            destination:
              server: https://kubernetes.default.svc
              namespace: ${namespace}
            source:
              repoURL: ghcr.io/akuity/kargo-charts
              chart: kargo
              targetRevision: 1.8.4
              helm:
                valuesObject:
                  api:
                    host: kargo.cnoe.localtest.me
                    adminAccount:
                      enabled: true
                      passwordHash: "$2b$10$bqVe5nszNR1eEt20jtNSle24cBsnhiiNcFHgZuMcv7HACZCD6a3IW"
                      tokenSigningKey: "pw4J0w4L2sMcvsbdWNPgWSeOuBm1IK0b"
                      tokenTTL: "24h"
                    service:
                      type: ClusterIP
                      port: 8080
                    grpcWeb: true
                    logLevel: INFO
                    tls:
                      enabled: false
                    ingress:
                      enabled: true
                      className: nginx
                      annotations:
                        nginx.ingress.kubernetes.io/backend-protocol: HTTP
                        nginx.ingress.kubernetes.io/grpc-backend: "true"
                      tls:
                        enabled: false
                    resources:
                      requests:
                        cpu: 100m
                        memory: 128Mi
                      limits:
                        cpu: 500m
                        memory: 256Mi
                  controller:
                    logLevel: INFO
                    resources:
                      requests:
                        cpu: 100m
                        memory: 128Mi
                      limits:
                        cpu: 500m
                        memory: 512Mi
                  webhooksServer:
                    enabled: true
                    tls:
                      selfSignedCert: false
                  webhooks:
                    register: false
                    logLevel: INFO
                    resources:
                      requests:
                        cpu: 100m
                        memory: 128Mi
                      limits:
                        cpu: 200m
                        memory: 256Mi
                  management:
                    logLevel: INFO
                    resources:
                      requests:
                        cpu: 50m
                        memory: 64Mi
                      limits:
                        cpu: 100m
                        memory: 128Mi
                  garbageCollector:
                    resources:
                      requests:
                        cpu: 50m
                        memory: 64Mi
                      limits:
                        cpu: 100m
                        memory: 128Mi
                  externalWebhooksServer:
                    enabled: true
                    tls:
                      enabled: false
                    incomingWebhooks:
                      github:
                        enabled: true
                        secretKeyRef:
                          name: kargo-github-webhook-secret
                          key: secret
                  awsLoadBalancerController:
                    enabled: false
                  rbac:
                    installClusterRoles: true
                    installClusterRoleBindings: true
                  certificates:
                    enabled: false
            syncPolicy:
              automated:
                prune: true
                selfHeal: true
              syncOptions:
                - CreateNamespace=true
                - ServerSideApply=true
        ''
      ];
    };
  };
}
