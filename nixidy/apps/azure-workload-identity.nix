# Azure Workload Identity Webhook
# Enables Kubernetes ServiceAccounts to authenticate to Azure AD using workload identity.
# Mutates ServiceAccount specs to include workload identity labels/annotations.
# Source: ref-implementation/azure-workload-identity/manifests/install.yaml
# KIND only - for local development with Azure Key Vault access
{ config, lib, ... }:
let
  isKind = config.environmentType == "kind";
  namespace = "azure-workload-identity-system";
  # Use tenant ID from config or placeholder from ref-implementation
  tenantId = if config.azure.tenantId != ""
             then config.azure.tenantId
             else "0c4da9c5-40ea-4e7d-9c7a-e7308d4f8e38";  # placeholder
  labels = {
    "app" = "workload-identity-webhook";
    "azure-workload-identity.io/system" = "true";
    "chart" = "workload-identity-webhook";
    "release" = "workload-identity-webhook";
  };
in
{
  config = lib.mkIf isKind {
    applications.azure-workload-identity = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "-90";
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
          replace = true;  # Required for webhooks
        };
      };

      yamls = [
        # PodDisruptionBudget
        ''
          apiVersion: policy/v1
          kind: PodDisruptionBudget
          metadata:
            labels:
              app: 'workload-identity-webhook'
              azure-workload-identity.io/system: "true"
              chart: 'workload-identity-webhook'
              release: 'workload-identity-webhook'
            name: azure-wi-webhook-controller-manager
            namespace: '${namespace}'
          spec:
            minAvailable: 1
            selector:
              matchLabels:
                app: 'workload-identity-webhook'
                azure-workload-identity.io/system: "true"
                chart: 'workload-identity-webhook'
                release: 'workload-identity-webhook'
        ''

        # ServiceAccount
        ''
          apiVersion: v1
          kind: ServiceAccount
          metadata:
            labels:
              app: 'workload-identity-webhook'
              azure-workload-identity.io/system: "true"
              chart: 'workload-identity-webhook'
              release: 'workload-identity-webhook'
            name: azure-wi-webhook-admin
            namespace: '${namespace}'
        ''

        # Secret for TLS cert
        ''
          apiVersion: v1
          kind: Secret
          metadata:
            labels:
              app: 'workload-identity-webhook'
              azure-workload-identity.io/system: "true"
              chart: 'workload-identity-webhook'
              release: 'workload-identity-webhook'
            name: azure-wi-webhook-server-cert
            namespace: '${namespace}'
        ''

        # ConfigMap with Azure tenant ID (templated)
        ''
          apiVersion: v1
          data:
            AZURE_ENVIRONMENT: AzurePublicCloud
            AZURE_TENANT_ID: ${tenantId}
          kind: ConfigMap
          metadata:
            labels:
              app: 'workload-identity-webhook'
              azure-workload-identity.io/system: "true"
              chart: 'workload-identity-webhook'
              release: 'workload-identity-webhook'
            name: azure-wi-webhook-config
            namespace: '${namespace}'
        ''

        # ClusterRole
        ''
          apiVersion: rbac.authorization.k8s.io/v1
          kind: ClusterRole
          metadata:
            labels:
              app: 'workload-identity-webhook'
              azure-workload-identity.io/system: "true"
              chart: 'workload-identity-webhook'
              release: 'workload-identity-webhook'
            name: azure-wi-webhook-manager-role
          rules:
          - apiGroups:
            - ""
            resources:
            - serviceaccounts
            verbs:
            - get
            - list
            - watch
          - apiGroups:
            - admissionregistration.k8s.io
            resources:
            - mutatingwebhookconfigurations
            verbs:
            - get
            - list
            - update
            - watch
        ''

        # ClusterRoleBinding
        ''
          apiVersion: rbac.authorization.k8s.io/v1
          kind: ClusterRoleBinding
          metadata:
            labels:
              app: 'workload-identity-webhook'
              azure-workload-identity.io/system: "true"
              chart: 'workload-identity-webhook'
              release: 'workload-identity-webhook'
            name: azure-wi-webhook-manager-rolebinding
          roleRef:
            apiGroup: rbac.authorization.k8s.io
            kind: ClusterRole
            name: azure-wi-webhook-manager-role
          subjects:
          - kind: ServiceAccount
            name: azure-wi-webhook-admin
            namespace: '${namespace}'
        ''

        # Role (namespace-scoped)
        ''
          apiVersion: rbac.authorization.k8s.io/v1
          kind: Role
          metadata:
            labels:
              app: 'workload-identity-webhook'
              azure-workload-identity.io/system: "true"
              chart: 'workload-identity-webhook'
              release: 'workload-identity-webhook'
            name: azure-wi-webhook-manager-role
            namespace: '${namespace}'
          rules:
          - apiGroups:
            - ""
            resources:
            - secrets
            verbs:
            - create
            - delete
            - get
            - list
            - patch
            - update
            - watch
        ''

        # RoleBinding
        ''
          apiVersion: rbac.authorization.k8s.io/v1
          kind: RoleBinding
          metadata:
            labels:
              app: 'workload-identity-webhook'
              azure-workload-identity.io/system: "true"
              chart: 'workload-identity-webhook'
              release: 'workload-identity-webhook'
            name: azure-wi-webhook-manager-rolebinding
            namespace: '${namespace}'
          roleRef:
            apiGroup: rbac.authorization.k8s.io
            kind: Role
            name: azure-wi-webhook-manager-role
          subjects:
          - kind: ServiceAccount
            name: azure-wi-webhook-admin
            namespace: '${namespace}'
        ''

        # Service
        ''
          apiVersion: v1
          kind: Service
          metadata:
            labels:
              app: 'workload-identity-webhook'
              azure-workload-identity.io/system: "true"
              chart: 'workload-identity-webhook'
              release: 'workload-identity-webhook'
            name: azure-wi-webhook-webhook-service
            namespace: '${namespace}'
          spec:
            type: ClusterIP
            ports:
            - port: 443
              targetPort: 9443
            selector:
              app: 'workload-identity-webhook'
              azure-workload-identity.io/system: "true"
              chart: 'workload-identity-webhook'
              release: 'workload-identity-webhook'
        ''

        # Deployment
        ''
          apiVersion: apps/v1
          kind: Deployment
          metadata:
            labels:
              app: 'workload-identity-webhook'
              azure-workload-identity.io/system: "true"
              chart: 'workload-identity-webhook'
              release: 'workload-identity-webhook'
            name: azure-wi-webhook-controller-manager
            namespace: '${namespace}'
          spec:
            replicas: 2
            selector:
              matchLabels:
                app: 'workload-identity-webhook'
                azure-workload-identity.io/system: "true"
                chart: 'workload-identity-webhook'
                release: 'workload-identity-webhook'
            template:
              metadata:
                labels:
                  app: 'workload-identity-webhook'
                  azure-workload-identity.io/system: "true"
                  chart: 'workload-identity-webhook'
                  release: 'workload-identity-webhook'
              spec:
                containers:
                - args:
                  - --log-level=info
                  - --metrics-addr=:8095
                  - --metrics-backend=prometheus
                  command:
                  - /manager
                  env:
                  - name: POD_NAMESPACE
                    valueFrom:
                      fieldRef:
                        apiVersion: v1
                        fieldPath: metadata.namespace
                  envFrom:
                  - configMapRef:
                      name: azure-wi-webhook-config
                  image: 'mcr.microsoft.com/oss/azure/workload-identity/webhook:v1.5.1'
                  imagePullPolicy: 'IfNotPresent'
                  livenessProbe:
                    failureThreshold: 6
                    httpGet:
                      path: /healthz
                      port: healthz
                    initialDelaySeconds: 15
                    periodSeconds: 20
                  name: manager
                  ports:
                  - containerPort: 8095
                    name: metrics
                    protocol: TCP
                  - containerPort: 9443
                    name: webhook-server
                    protocol: TCP
                  - containerPort: 9440
                    name: healthz
                    protocol: TCP
                  readinessProbe:
                    httpGet:
                      path: /readyz
                      port: healthz
                    initialDelaySeconds: 5
                    periodSeconds: 5
                  resources:
                    limits:
                      cpu: 100m
                      memory: 30Mi
                    requests:
                      cpu: 100m
                      memory: 20Mi
                  securityContext:
                    allowPrivilegeEscalation: false
                    capabilities:
                      drop:
                      - ALL
                    readOnlyRootFilesystem: true
                    runAsGroup: 65532
                    runAsNonRoot: true
                    runAsUser: 65532
                    seccompProfile:
                      type: RuntimeDefault
                  volumeMounts:
                  - mountPath: /certs
                    name: cert
                    readOnly: true
                nodeSelector:
                  kubernetes.io/os: linux
                priorityClassName: system-cluster-critical
                serviceAccountName: azure-wi-webhook-admin
                volumes:
                - name: cert
                  secret:
                    defaultMode: 420
                    secretName: azure-wi-webhook-server-cert
        ''

        # MutatingWebhookConfiguration
        ''
          apiVersion: admissionregistration.k8s.io/v1
          kind: MutatingWebhookConfiguration
          metadata:
            labels:
              app: 'workload-identity-webhook'
              azure-workload-identity.io/system: "true"
              chart: 'workload-identity-webhook'
              release: 'workload-identity-webhook'
            name: azure-wi-webhook-mutating-webhook-configuration
          webhooks:
          - admissionReviewVersions:
            - v1
            - v1beta1
            clientConfig:
              service:
                name: azure-wi-webhook-webhook-service
                namespace: '${namespace}'
                path: /mutate-v1-pod
            failurePolicy: Fail
            matchPolicy: Equivalent
            name: mutation.azure-workload-identity.io
            objectSelector:
              matchLabels:
                azure.workload.identity/use: "true"
            reinvocationPolicy: IfNeeded
            rules:
            - apiGroups:
              - ""
              apiVersions:
              - v1
              operations:
              - CREATE
              resources:
              - pods
            sideEffects: None
        ''
      ];
    };
  };
}
