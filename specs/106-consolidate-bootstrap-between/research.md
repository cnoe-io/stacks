# Research: Consolidate Bootstrap Between KIND and Talos Clusters

**Feature**: 106-consolidate-bootstrap-between
**Date**: 2025-12-07

## Executive Summary

Analysis of existing KIND (`scripts/wi-kind-lib.sh`, `deployment/scripts/cluster-menu.sh`) and Talos (`scripts/bootstrap-cluster.sh`, `scripts/lib/`) scripts reveals significant overlap in Azure infrastructure and common utilities, but meaningful architectural differences in cluster creation and deployment strategies that justify keeping those areas distinct.

---

## Research Areas

### 1. Cluster Type Detection Strategy

**Decision**: Use kubectl context name pattern + available tools (talosctl, kind CLI) for detection

**Rationale**:
- KIND clusters have context names starting with `kind-` (e.g., `kind-gitops`, `kind-localdev`)
- Talos clusters can be detected by presence of `talosctl` with valid configuration
- This approach already exists in `deployment/scripts/cluster-menu.sh`:
  ```bash
  detect_host_context() {
    local ctx
    ctx=$(kubectl config get-contexts -o name 2>/dev/null | grep '^kind-' | tail -1)
    # ...
  }
  ```

**Alternatives considered**:
- Environment variable only (`CLUSTER_TYPE`): Rejected because it requires manual setting and can drift from actual cluster
- Cluster API version check: Rejected because both use same K8s version
- Node labels/annotations: Rejected because requires cluster to be running

**Implementation pattern**:
```bash
detect_cluster_type() {
    # Explicit override takes precedence
    [[ -n "${CLUSTER_TYPE:-}" ]] && echo "$CLUSTER_TYPE" && return

    # Check kubectl context for KIND pattern
    local ctx=$(kubectl config current-context 2>/dev/null || echo "")
    [[ "$ctx" == kind-* ]] && echo "kind" && return

    # Check for talosctl with valid config
    if command -v talosctl &>/dev/null; then
        talosctl config info &>/dev/null 2>&1 && echo "talos" && return
    fi

    # Default to kind if context exists
    [[ -n "$ctx" ]] && echo "kind" && return

    echo "unknown"
}
```

---

### 2. Environment File Strategy

**Decision**: Use `.env-files/{cluster_type}.env` pattern with direnv auto-loading

**Rationale**:
- Already implemented in Talos bootstrap (`.env-files/talos.env`)
- KIND uses `.env-files/wi.env` but should be renamed to `.env-files/kind.env` for consistency
- direnv provides automatic loading and watching for changes

**Current state**:
| Cluster | Env File | Variables |
|---------|----------|-----------|
| KIND | `.env-files/wi.env` | AZURE_CLIENT_ID, SERVICE_ACCOUNT_ISSUER, AZURE_STORAGE_ACCOUNT, etc. |
| Talos | `.env-files/talos.env` | AZURE_CLIENT_ID, SERVICE_ACCOUNT_ISSUER, AZURE_STORAGE_ACCOUNT, etc. |

**Shared variables** (identical across both):
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_TENANT_ID`
- `AZURE_CLIENT_ID`
- `AZURE_KEYVAULT_NAME`
- `ACR_NAME`, `ACR_RG`
- `GH_APP_ID`, `GH_INSTALLATION_ID`
- `ENVIRONMENT`, `NODE_ENV`
- `ENABLE_TLS`, `TLS_ISSUER`, `INGRESS_HOST`

**Cluster-specific variables**:
| Variable | KIND | Talos |
|----------|------|-------|
| `CLUSTER_TYPE` | `kind` | `talos` |
| `SERVICE_ACCOUNT_ISSUER` | Different storage account URL | Different storage account URL |
| `AZURE_STORAGE_ACCOUNT` | `oidcissuer65846b7df97b` | `oidcissuerf6ddc8e2f2fb` |
| `RESOURCE_GROUP` | `rg4` | `rg-talos-dev` |
| `CLUSTER_NAME` | `kind` or `gitops` | `talos-cluster` |

**Alternatives considered**:
- Single `.env` file with conditional logic: Rejected because it makes switching difficult
- Database/config service: Rejected as over-engineered for shell scripts
- Kubernetes ConfigMaps: Rejected because needed before cluster exists

---

### 3. Azure Infrastructure Consolidation

**Decision**: Fully consolidate Azure AD app and federated credential logic into `scripts/lib/azure.sh`

**Rationale**:
- Azure AD apps are identical regardless of cluster type
- Federated credentials use same OIDC flow
- Only difference is the `SERVICE_ACCOUNT_ISSUER` URL (parameterized)

**Current duplication analysis**:

| Function | KIND (`wi-kind-lib.sh`) | Talos (`scripts/lib/azure.sh`) | Action |
|----------|-------------------------|--------------------------------|--------|
| Azure login check | `require_az_login()` | `validate_azure_login()` | Consolidate |
| AD app creation | Complex in various funcs | `create_azure_ad_app()` | Use Talos pattern |
| Federated creds | `ensure_federated_credentials()` | `create_federated_credential()` | Use Talos pattern |
| Key Vault access | `get_keyvault_secret()` | `get_keyvault_secret()` | Consolidate |
| Storage upload | `upload_to_web_container()` | `upload_to_web_container()` | Consolidate |

**Lines of code analysis**:
- KIND `wi-kind-lib.sh`: ~74,000 bytes (includes much non-Azure code)
- Talos `scripts/lib/azure.sh`: ~5,225 bytes (clean, focused)

**Recommendation**: Use Talos pattern as base, it's cleaner and more modular.

---

### 4. CDK8s Synthesis Strategy

**Decision**: Use environment variable `CLUSTER_TYPE` to determine ArgoCD source URL patterns

**Rationale**:
- CDK8s charts are 95% identical between cluster types
- Only ArgoCD Application source URLs differ:
  - KIND: `cnoe://<app>/manifests` (idpBuilder local)
  - Talos: `https://github.com/PittampalliOrg/stacks.git` (GitHub direct)

**Implementation approach**:
```typescript
// In ArgoCD chart configuration
const getSourceUrl = (appName: string): string => {
  const env = process.env.ENVIRONMENT || 'dev';
  const clusterType = process.env.CLUSTER_TYPE || 'kind';

  if (clusterType === 'kind' && env === 'dev') {
    return `cnoe://${appName}/manifests`;
  }
  return process.env.GIT_REPO_URL || 'https://github.com/PittampalliOrg/stacks.git';
};
```

**Existing pattern** (from `cdk8s/config/applications.ts`):
```typescript
// Already uses environment detection
const environment = process.env.ENVIRONMENT || 'dev';
```

**Alternatives considered**:
- Separate synthesis scripts per cluster: Rejected because 95% code duplication
- Build-time configuration injection: Possible but more complex
- Runtime detection: Not applicable for manifest generation

---

### 5. Deployment Strategy Differences

**Decision**: Keep deployment strategies distinct with a common interface

**Rationale**: Architectural differences make consolidation counterproductive:

| Aspect | KIND | Talos |
|--------|------|-------|
| ArgoCD install | idpBuilder creates packages | Helm chart installation |
| Manifest apply | idpBuilder pushes to Gitea | kubectl apply / Git push |
| Ingress | idpBuilder nginx-ingress | External ingress (Tailscale) |
| Local Git | Gitea in-cluster | External GitHub |

**Interface pattern**:
```bash
# Abstract function in bootstrap-cluster.sh
deploy_argocd() {
    case "$CLUSTER_TYPE" in
        kind)
            deploy_argocd_kind "$@"
            ;;
        talos)
            deploy_argocd_talos "$@"
            ;;
        *)
            log_error "Unknown cluster type: $CLUSTER_TYPE"
            return 1
            ;;
    esac
}
```

**Cluster-specific implementations**:
- `scripts/lib/kind.sh` - KIND-specific deployment (idpBuilder)
- `scripts/lib/talos.sh` - Talos-specific deployment (Helm)

---

### 6. Common Utilities Consolidation

**Decision**: Consolidate logging, retry, validation into `scripts/lib/common.sh`

**Current state**:
- KIND: Scattered logging in `wi-kind-lib.sh` (`log()` function)
- Talos: Clean utilities in `scripts/lib/common.sh` (log_info, log_success, log_warn, log_error)

**Functions to consolidate**:
| Function | Purpose |
|----------|---------|
| `log_info` | Informational messages |
| `log_success` | Success messages |
| `log_warn` | Warning messages |
| `log_error` | Error messages |
| `print_header` | Section headers |
| `retry_with_backoff` | Exponential retry |
| `require_env` | Validate environment variable |
| `require_tool` | Validate CLI tool available |

**Already consolidated** in Talos implementation (`scripts/lib/common.sh`):
- Color output detection
- Logging functions
- Header printing
- Retry logic
- Environment validation

---

### 7. JWKS/OIDC Configuration

**Decision**: Keep OIDC configuration as part of Azure setup, but parameterize storage account

**Rationale**:
- Both clusters use Azure Storage for OIDC discovery
- Storage account URL differs but logic is identical
- JWKS sync (`scripts/02-sync-jwks.sh`) can be shared

**Current JWKS flow**:
1. Extract JWKS from cluster API server
2. Generate `openid-configuration` JSON
3. Upload both to Azure Storage static website
4. Configure `SERVICE_ACCOUNT_ISSUER` to point to storage URL

**Parameterization**:
```bash
sync_jwks() {
    local storage_account="${AZURE_STORAGE_ACCOUNT:?Required}"
    local issuer_url="${SERVICE_ACCOUNT_ISSUER:?Required}"

    # Extract JWKS (cluster-agnostic)
    kubectl get --raw /openid/v1/jwks > /tmp/jwks.json

    # Upload to storage (parameterized)
    upload_to_web_container "$storage_account" ".well-known/openid-configuration" ...
    upload_to_web_container "$storage_account" "openid/v1/jwks" ...
}
```

---

## Consolidation Scorecard

| Area | Consolidation Value | Effort | Recommendation |
|------|---------------------|--------|----------------|
| Azure AD app management | High | Low | ✅ Consolidate |
| Common utilities | High | Low | ✅ Consolidate |
| direnv configuration | High | Low | ✅ Consolidate |
| Environment validation | High | Low | ✅ Consolidate |
| CDK8s synthesis core | High | Medium | ✅ Consolidate |
| ArgoCD installation | Low | High | ❌ Keep distinct |
| Manifest deployment | Low | High | ❌ Keep distinct |
| Cluster creation | N/A | N/A | ❌ Keep distinct |

---

## Implementation Strategy

### Phase 1: Common Foundation (Low Risk)
1. Rename `.env-files/wi.env` to `.env-files/kind.env`
2. Update root `.envrc` with unified cluster detection
3. Verify `scripts/lib/common.sh` works for both clusters
4. Add `detect_cluster_type()` to common.sh

### Phase 2: Azure Consolidation (Medium Risk)
1. Merge KIND Azure functions into `scripts/lib/azure.sh`
2. Update bootstrap-cluster.sh to work with both clusters
3. Test Azure AD app idempotency on both clusters

### Phase 3: CDK8s Unification (Medium Risk)
1. Add `CLUSTER_TYPE` environment check to synthesis
2. Update ArgoCD source URL logic
3. Test synthesis for both cluster types

### Phase 4: Deployment Abstraction (Low Risk)
1. Create `scripts/lib/kind.sh` for KIND-specific deployment
2. Keep `scripts/lib/talos.sh` for Talos-specific deployment
3. Add deployment dispatcher to unified bootstrap

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Break existing KIND workflow | Medium | High | Keep `wi-kind-lib.sh` as fallback during transition |
| Environment file migration issues | Low | Medium | Document migration steps clearly |
| CDK8s synthesis regression | Medium | High | Add CI tests for both cluster types |
| Azure credential confusion | Low | High | Validate env vars early in bootstrap |

---

## References

- Existing KIND scripts: `scripts/wi-kind-lib.sh`, `deployment/scripts/cluster-menu.sh`
- Existing Talos scripts: `scripts/bootstrap-cluster.sh`, `scripts/lib/`
- Environment files: `.env-files/wi.env`, `.env-files/talos.env`
- CDK8s config: `cdk8s/config/applications.ts`, `cdk8s/main-v2.ts`
