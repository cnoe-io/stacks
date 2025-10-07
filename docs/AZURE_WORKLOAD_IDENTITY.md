# Azure Workload Identity Integration

## Current Setup

Azure Workload Identity webhook is deployed in the cluster and ready for use. The webhook intercepts pod creation and injects the necessary environment variables and volume mounts for pods that need to authenticate with Azure services.

## When to Add Azure Workload Identity Annotations

You should add the `azure.workload.identity/client-id` annotation to a ServiceAccount when:

1. **External Secrets with Azure Key Vault**: If you configure External Secrets Operator to use Azure Key Vault as a SecretStore/ClusterSecretStore
   ```yaml
   apiVersion: external-secrets.io/v1beta1
   kind: ClusterSecretStore
   metadata:
     name: azure-keyvault
   spec:
     provider:
       azurekv:
         vaultUrl: "https://your-keyvault.vault.azure.net"
         authType: WorkloadIdentity
         serviceAccountRef:
           name: external-secrets
           namespace: external-secrets
   ```

2. **Application Access to Azure Storage**: If your application needs to access Azure Blob Storage, Azure Files, etc.

3. **Application Access to Azure Databases**: If your application needs to authenticate to Azure SQL, CosmosDB, etc. using managed identity

4. **Azure Service Bus/Event Hubs**: If your application needs to publish/consume messages from Azure messaging services

## How to Enable Azure Workload Identity for a ServiceAccount

1. Add the annotation to the ServiceAccount:
   ```yaml
   apiVersion: v1
   kind: ServiceAccount
   metadata:
     name: my-app
     namespace: my-namespace
     annotations:
       azure.workload.identity/client-id: "85d36f23-295a-436f-8754-a03491a434a6"  # Your Azure AD App Client ID
   ```

2. Add the label to pods that should use this identity:
   ```yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: my-pod
     labels:
       azure.workload.identity/use: "true"
   spec:
     serviceAccountName: my-app
   ```

## Current ServiceAccounts That DO NOT Need Azure Workload Identity

The following ServiceAccounts are used for internal Kubernetes secret management and do NOT need Azure Workload Identity annotations:

- `eso-store` in namespaces: keycloak, gitea, argocd, backstage
  - These are used by External Secrets to read Kubernetes secrets within the cluster
  - They use the Kubernetes provider, not Azure Key Vault

## Testing Azure Workload Identity

Use the test pod in `/home/vscode/stacks/ref-implementation/test-workload-identity.yaml` to verify the setup is working correctly.