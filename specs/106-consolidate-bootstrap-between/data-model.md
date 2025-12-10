# Data Model: Consolidate Bootstrap Between KIND and Talos Clusters

**Feature**: 106-consolidate-bootstrap-between
**Date**: 2025-12-07

## Overview

This document defines the data entities and configuration structures for the unified cluster bootstrap system. The model focuses on environment configuration, cluster metadata, and Azure resource representation.

---

## Core Entities

### ClusterType

Enumeration of supported cluster types with associated behaviors.

```
ClusterType
├── value: string ("kind" | "talos")
├── envFile: string (path to .env-files/{type}.env)
├── deploymentStrategy: DeploymentStrategy
└── features: ClusterFeatures
```

**Validation Rules**:
- Value must be one of: "kind", "talos"
- envFile must exist and be readable
- deploymentStrategy must match cluster type

**State Transitions**: None (immutable enum)

---

### EnvironmentConfig

Cluster-specific configuration loaded from environment files.

```
EnvironmentConfig
├── clusterType: ClusterType
├── azure: AzureConfig
├── git: GitConfig
├── ingress: IngressConfig
└── workloadIdentity: WorkloadIdentityConfig
```

**Relationships**:
- One EnvironmentConfig per cluster
- Contains one AzureConfig
- Contains one GitConfig
- Contains one IngressConfig
- Contains one WorkloadIdentityConfig

---

### AzureConfig

Azure-specific configuration for workload identity and Key Vault access.

```
AzureConfig
├── subscriptionId: string (UUID)
├── tenantId: string (UUID)
├── clientId: string (UUID, Azure AD app)
├── keyVaultName: string (without .vault.azure.net)
├── storageAccount: string (OIDC static website)
├── resourceGroup: string
├── location: string (default: "eastus")
└── acrName: string (optional, container registry)
```

**Validation Rules**:
- All UUID fields must be valid UUID format
- keyVaultName must be 3-24 characters, alphanumeric and hyphens
- storageAccount must be 3-24 characters, lowercase alphanumeric only
- resourceGroup must exist in Azure

---

### GitConfig

Git repository configuration for ArgoCD source.

```
GitConfig
├── repoUrl: string (GitHub URL or cnoe:// URL)
├── branch: string (default: "main")
├── appId: string (GitHub App ID, optional)
└── installationId: string (GitHub App Installation ID, optional)
```

**Validation Rules**:
- For Talos: repoUrl must be valid HTTPS GitHub URL
- For KIND: repoUrl can be cnoe:// URL or GitHub URL
- branch must be valid git branch name

---

### IngressConfig

Ingress and TLS configuration.

```
IngressConfig
├── host: string (domain name)
├── enableTls: boolean
├── tlsIssuer: string (cert-manager issuer name, optional)
└── externalUrl: string (full URL with protocol)
```

**Validation Rules**:
- host must be valid domain name
- If enableTls is true and tlsIssuer is empty, use default issuer
- externalUrl must include protocol (http:// or https://)

---

### WorkloadIdentityConfig

Kubernetes workload identity configuration.

```
WorkloadIdentityConfig
├── serviceAccountIssuer: string (OIDC issuer URL with trailing slash)
├── serviceAccounts: ServiceAccountRef[]
└── audiences: string[] (default: ["api://AzureADTokenExchange"])
```

**Validation Rules**:
- serviceAccountIssuer must end with `/`
- serviceAccountIssuer must match Azure Storage static website URL
- serviceAccounts must have at least one entry

---

### ServiceAccountRef

Reference to a Kubernetes ServiceAccount for federated credentials.

```
ServiceAccountRef
├── namespace: string
├── name: string
└── credentialName: string (derived: "{namespace}-{name}")
```

**Validation Rules**:
- namespace must be valid Kubernetes namespace name
- name must be valid Kubernetes ServiceAccount name
- Combined length must not exceed federated credential name limits

---

### AzureAdApp

Azure AD application for workload identity federation.

```
AzureAdApp
├── displayName: string ("gitops-{clusterType}-{clusterName}")
├── clientId: string (UUID, immutable after creation)
├── objectId: string (UUID, immutable after creation)
├── federatedCredentials: FederatedCredential[]
└── createdAt: timestamp
```

**State Transitions**:
```
NotExists -> Created (via az ad app create)
Created -> Updated (via az ad app federated-credential create)
```

---

### FederatedCredential

Azure AD federated credential for a Kubernetes ServiceAccount.

```
FederatedCredential
├── name: string ("{namespace}-{serviceAccountName}")
├── issuer: string (OIDC issuer URL with trailing slash)
├── subject: string ("system:serviceaccount:{namespace}:{name}")
├── audiences: string[]
└── createdAt: timestamp
```

**Validation Rules**:
- issuer must end with `/` (critical for OIDC matching)
- subject must follow Kubernetes ServiceAccount subject format
- audiences must include "api://AzureADTokenExchange"

---

### BootstrapPhase

Named phases of the bootstrap process for resumability.

```
BootstrapPhase
├── name: string (enum below)
├── status: PhaseStatus ("pending" | "in_progress" | "completed" | "failed")
├── startedAt: timestamp (optional)
├── completedAt: timestamp (optional)
└── errorMessage: string (optional)
```

**Phase Names** (in order):
1. `init` - Initial state
2. `validate` - Validate prerequisites
3. `azure-setup` - Azure AD app and federated credentials
4. `synth` - CDK8s synthesis
5. `deploy` - ArgoCD and manifest deployment
6. `verify` - Verify deployment success

---

### DeploymentStrategy

Cluster-specific deployment approach.

```
DeploymentStrategy
├── type: string ("idpbuilder" | "helm")
├── argocdInstallMethod: string
├── manifestApplyMethod: string
└── postDeployHooks: string[]
```

**Values by Cluster Type**:

| ClusterType | argocdInstallMethod | manifestApplyMethod |
|-------------|---------------------|---------------------|
| kind | `idpbuilder create --package` | Push to Gitea via idpBuilder |
| talos | `helm install argocd argo/argo-cd` | `kubectl apply` or Git push |

---

## Environment File Structure

### `.env-files/kind.env` (rename from wi.env)

```env
# Cluster Identity
CLUSTER_TYPE=kind
CLUSTER_NAME=gitops
ENVIRONMENT=dev

# Azure Core
AZURE_SUBSCRIPTION_ID=<uuid>
AZURE_TENANT_ID=<uuid>
AZURE_CLIENT_ID=<uuid>
AZURE_KEYVAULT_NAME=<keyvault-name>
AZURE_STORAGE_ACCOUNT=<storage-account>
RESOURCE_GROUP=<resource-group>

# Workload Identity
SERVICE_ACCOUNT_ISSUER=https://<storage>.z13.web.core.windows.net/
WORKLOAD_IDENTITY_SERVICE_ACCOUNTS="external-secrets:external-secrets"

# Git
GIT_REPO_URL=cnoe://
GH_APP_ID=<app-id>
GH_INSTALLATION_ID=<installation-id>

# Ingress
INGRESS_HOST=cnoe.localtest.me
ENABLE_TLS=true
```

### `.env-files/talos.env`

```env
# Cluster Identity
CLUSTER_TYPE=talos
CLUSTER_NAME=talos-cluster
ENVIRONMENT=dev

# Azure Core
AZURE_SUBSCRIPTION_ID=<uuid>
AZURE_TENANT_ID=<uuid>
AZURE_CLIENT_ID=<uuid>
AZURE_KEYVAULT_NAME=<keyvault-name>
AZURE_STORAGE_ACCOUNT=<storage-account>
RESOURCE_GROUP=<resource-group>

# Workload Identity
SERVICE_ACCOUNT_ISSUER=https://<storage>.z13.web.core.windows.net/
WORKLOAD_IDENTITY_SERVICE_ACCOUNTS="external-secrets:external-secrets kargo:acr-sa mcp-tools:acr-sa"

# Git
GIT_REPO_URL=https://github.com/PittampalliOrg/stacks.git
GIT_BRANCH=main

# Ingress
INGRESS_HOST=talos.cnoe.localtest.me
ENABLE_TLS=true
TLS_ISSUER=letsencrypt-prod
```

---

## Entity Relationships

```
EnvironmentConfig
    │
    ├──> AzureConfig
    │       │
    │       └──> AzureAdApp
    │               │
    │               └──> FederatedCredential[] (1:many)
    │
    ├──> WorkloadIdentityConfig
    │       │
    │       └──> ServiceAccountRef[] (1:many)
    │
    ├──> GitConfig
    │
    └──> IngressConfig

ClusterType
    │
    └──> DeploymentStrategy (1:1)

BootstrapPhase[] (ordered sequence per cluster)
```

---

## Validation Summary

### Pre-Bootstrap Validation

| Check | Kind | Talos | Error Message |
|-------|------|-------|---------------|
| kubectl context | Required | Required | "No kubectl context found" |
| talosctl config | N/A | Required | "talosctl not configured" |
| Azure CLI login | Required | Required | "Run: az login" |
| Environment file | Required | Required | "Missing .env-files/{type}.env" |
| AZURE_SUBSCRIPTION_ID | Required | Required | "AZURE_SUBSCRIPTION_ID not set" |
| AZURE_CLIENT_ID | Required | Required | "AZURE_CLIENT_ID not set" |
| SERVICE_ACCOUNT_ISSUER | Required | Required | "SERVICE_ACCOUNT_ISSUER not set" |
| Trailing slash on issuer | Required | Required | "SERVICE_ACCOUNT_ISSUER must end with /" |

### Post-Bootstrap Validation

| Check | Kind | Talos | Verification Method |
|-------|------|-------|---------------------|
| ArgoCD running | Required | Required | `kubectl get pods -n argocd` |
| ArgoCD accessible | Required | Required | `curl https://<ingress>/argocd/api/version` |
| ESO controller running | Required | Required | `kubectl get pods -n external-secrets` |
| ClusterSecretStore ready | Required | Required | `kubectl get clustersecretstore` |
