# ArgoCD GitOps Bootstrap

Bootstraps ArgoCD and all platform services on a Talos cluster via GitOps.

## Prerequisites

- Talos cluster running with kubectl access (see [hcloud-server-setup.md](hcloud-server-setup.md))
- Azure infrastructure configured (`scripts/00-bootstrap-azure-infra.sh`)
- CDK8s manifests synthesized and pushed to Git

## Quick Start

```bash
export KUBECONFIG=~/repos/PittampalliOrg/stacks/106-consolidate-bootstrap-between/talos-configs/kubeconfig
cd ~/repos/PittampalliOrg/stacks/106-consolidate-bootstrap-between/scripts

./bootstrap-argocd.sh
```

That's it. The script handles everything:
1. Removes control-plane taints (if CP-only cluster)
2. Syncs JWKS to Azure Storage (for Workload Identity)
3. Installs ArgoCD via Helm
4. Applies root ArgoCD Application
5. ArgoCD auto-sync deploys all apps via sync waves

## What Gets Deployed

ArgoCD auto-syncs applications in dependency order (sync waves):

| Wave | Application | Purpose |
|------|-------------|---------|
| -150 | argocd-config | Ingress health check (Talos has no ingress controller) |
| -105 | local-path-provisioner | Storage for PVCs |
| -100 | external-secrets-operator | ESO via Helm |
| -94 | workload-identity-patch | Azure WI annotations on ServiceAccount |
| -92 | cluster-secret-store | ClusterSecretStore for Azure Key Vault |
| -60+ | Platform services | Tailscale, kagent, observability, etc. |

## Monitoring Progress

```bash
# Watch applications sync
kubectl get applications -n argocd -w

# Check specific app
kubectl get application <app-name> -n argocd -o yaml

# ArgoCD UI (port-forward)
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080, user: admin
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
```

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Apps stuck "Progressing" | Ingress waiting for address | Check `argocd-config` app synced first |
| ExternalSecrets errors | ServiceAccount missing WI annotations | Check `workload-identity-patch` synced |
| ClusterSecretStore not ready | ESO has old tokens | `kubectl rollout restart deployment -n external-secrets --all` |
| ArgoCD pods Pending | CP taints not removed | `kubectl taint nodes --all node-role.kubernetes.io/control-plane-` |

## Manual Bootstrap (Debug)

If the script fails, run steps individually:

```bash
# 1. Remove taints
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

# 2. Sync JWKS
set -a && source .env && set +a
./02-sync-jwks.sh

# 3. Install ArgoCD
./01-install-argocd.sh

# 4. Apply root app
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd-bootstrap
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/PittampalliOrg/stacks.git
    path: cdk8s/dist
    targetRevision: 106-consolidate-bootstrap-between
    directory:
      recurse: false
      include: '*.yaml'
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true, ServerSideApply=true]
EOF
```

## CDK8s Re-synthesis

If you need to update manifests:

```bash
cd cdk8s
export AZURE_CLIENT_ID="..." AZURE_TENANT_ID="..." AZURE_KEYVAULT_NAME="..."
npm run synth:talos

cd ..
git add cdk8s/dist/ && git commit -m "chore: Re-synthesize manifests" && git push
```

ArgoCD will auto-sync the changes.
