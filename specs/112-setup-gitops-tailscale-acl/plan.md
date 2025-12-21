# Implementation Plan: GitOps for Tailscale ACLs

**Branch**: `112-setup-gitops-tailscale-acl` | **Date**: 2025-12-21  
**Reference**: Tailscale “GitOps ACLs with GitHub” (tailscale.com/kb/1306/gitops-acls-github)

## Summary

Manage the tailnet ACL policy as code (HuJSON) in this repo and continuously validate/apply it via GitHub Actions. This removes manual edits in the Tailscale Admin Console for:
- `tagOwners` (e.g., `tag:k8s-operator`, `tag:k8s-services`)
- `autoApprovers` for Tailscale Services (e.g., `svc:argocd`, `svc:k8s-api-hub`)
- `grants` required for Kubernetes Operator API Server Proxy identity impersonation

## Current Architecture (Repo Review)

### CDK8s synthesis + ArgoCD GitOps
- `cdk8s/main.ts` synthesizes per-app manifests and also emits an ArgoCD `Application` per app into `cdk8s/dist/`.
- `.github/workflows/render-manifests.yml` renders manifests for `kind` and `talos`, and pushes them to `rendered/<cluster-type>/<branch>` branches.
- `cdk8s/config/applications.ts` is the declarative inventory of platform apps (sync waves, namespaces, chart props).

### Tailscale in cluster
- `tailscale-operator` deployed via `cdk8s/charts/infra/tailscale-operator-chart.ts` using OAuth credentials synced via External Secrets.
- Tailscale “Services” access via `cdk8s/charts/platform/tailscale-serve-chart.ts` using `tailscale serve --service=svc:<name>`.
- `tailscale-secrets` syncs `TAILSCALE-AUTH-KEY` from Azure Key Vault into `tailscale-auth-key` secret for service pods.
- Some service names are host-aware in `cdk8s/config/applications.ts` (via `CLUSTER_HOST`) to avoid collisions across machines.

## Desired End State

1. `policy.hujson` in Git is the source of truth for tailnet ACL policy.
2. PRs validate policy (“test”) before merge.
3. Merges to `main` apply policy (“apply”) automatically.
4. Kubernetes/Tailscale assumptions in `cdk8s/config/applications.ts` are reflected in policy:
   - Tags exist and are owned appropriately.
   - Service auto-approvers cover all `svc:*` names used by charts.
   - Kubernetes capability grants exist for operator API proxy.

## Implementation Steps

### Phase 1: Enable GitOps mechanics (CI)
1. Add `policy.hujson` to repo root.
2. Add `.github/workflows/tailscale-acl.yml`:
   - `pull_request`: run `tailscale/gitops-acl-action@v1` with `action: test`
   - `push` to `main`: run `action: apply`

### Phase 2: Configure Tailscale credentials for CI
1. Create a Tailscale OAuth client with permissions to manage ACLs for the tailnet.
2. Add GitHub repo secrets:
   - `TS_TAILNET`
   - `TS_OAUTH_ID`
   - `TS_OAUTH_SECRET`

### Phase 3: Encode required policy for this stack
1. `tagOwners` for:
   - `tag:k8s-operator`
   - `tag:k8s-services`
   - (optional) `tag:k8s` (subnet routing)
2. `autoApprovers.services` entries for all service names used in `cdk8s/config/applications.ts`:
   - non-suffixed (`svc:argocd`, `svc:k8s-api`, `svc:otel-collector`, …)
   - suffixed variants when using `CLUSTER_HOST` (e.g., `svc:argocd-ryzen`, …)
   - hub variants (e.g., `svc:argocd-hub`, `svc:kargo-hub`)
3. `grants` for `tailscale.com/cap/kubernetes` for `tag:k8s-operator` (API server proxy auth mode).

### Phase 4: Guardrails (recommended)
1. Add branch protection requiring review for `policy.hujson` changes.
2. Add `CODEOWNERS` entry for `policy.hujson`.
3. Optional: add “break-glass” docs for reverting from Git in case of lockout.

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Bad policy locks out access | High | PR validation + branch protections + keep a known-good policy revision |
| Service names drift vs. policy | Medium | Treat `cdk8s/config/applications.ts` and `policy.hujson` as a coupled change |

