# Quickstart: Backstage CDK8s Chart Migration

**Date**: 2025-12-09
**Feature**: 104-backstage-talos

## Prerequisites

- Node.js 18+ and npm
- kubectl configured for target cluster
- idpBuilder installed (for KIND deployment)
- Access to existing ref-implementation manifests

## Quick Validation

### 1. Synthesize Charts

```bash
cd cdk8s
npm run synth
```

Expected output:
```
═══════════════════════════════════════════════════════════════
  Unified CDK8s Synthesis
  Cluster Type: KIND
═══════════════════════════════════════════════════════════════

🔧 Auto-registering charts...
  Registered: XX chart types
✓ Auto-registered XX charts in XXms

🚀 Starting synthesis with 4 workers...
   Cluster Type: kind
   Applications: XX (filtered from XX)
   Output: dist/

Synthesizing application: backstage-secrets
  ✓ Generated resources for backstage-secrets
  ✓ Generated kustomization.yaml
  ✓ Moved ArgoCD Application to package root
✓ Successfully synthesized: backstage-secrets

Synthesizing application: backstage
  ✓ Generated resources for backstage
  ✓ Generated kustomization.yaml
  ✓ Moved ArgoCD Application to package root
✓ Successfully synthesized: backstage

✅ Synthesis complete!
```

### 2. Verify Output Structure

```bash
ls -la dist/backstage/
```

Expected:
```
backstage.yaml              # ArgoCD Application
manifests/
├── kustomization.yaml
├── KubeNamespace.*.yaml
├── KubeServiceAccount.*.yaml
├── KubeClusterRole.*.yaml
├── KubeClusterRoleBinding.*.yaml
├── KubeService.*.yaml
├── KubeDeployment.*.yaml
├── KubeStatefulSet.*.yaml
└── KubeIngress.*.yaml
```

```bash
ls -la dist/backstage-secrets/
```

Expected:
```
backstage-secrets.yaml      # ArgoCD Application
manifests/
├── kustomization.yaml
├── Password.*.yaml
├── ExternalSecret.*.yaml
├── KubeServiceAccount.*.yaml
├── KubeRole.*.yaml
├── KubeRoleBinding.*.yaml
└── ClusterSecretStore.*.yaml
```

### 3. Count Resources

```bash
# BackstageChart should produce 11 resources
ls dist/backstage/manifests/*.yaml | grep -v kustomization | wc -l
# Expected: 11

# BackstageSecretsChart should produce 10 resources
ls dist/backstage-secrets/manifests/*.yaml | grep -v kustomization | wc -l
# Expected: 10
```

### 4. Compare with Reference Implementation

```bash
# Concatenate synthesized manifests
cat dist/backstage/manifests/*.yaml dist/backstage-secrets/manifests/*.yaml \
  | grep -v "^#" | grep -v "^---$" > /tmp/synthesized.yaml

# Compare resource types
echo "=== Synthesized Resources ==="
grep "^kind:" /tmp/synthesized.yaml | sort | uniq -c

echo "=== Reference Resources ==="
cat ref-implementation/backstage/manifests/*.yaml \
  | grep "^kind:" | sort | uniq -c
```

Expected (both should match):
```
      2 kind: ClusterRole
      2 kind: ClusterRoleBinding
      1 kind: ClusterSecretStore
      1 kind: Deployment
      4 kind: ExternalSecret
      1 kind: Ingress
      1 kind: Namespace
      2 kind: Password
      1 kind: Role
      1 kind: RoleBinding
      2 kind: Service
      2 kind: ServiceAccount
      1 kind: StatefulSet
```

## Deploy to KIND Cluster

### 1. Deploy via idpBuilder

```bash
# From repository root
idpbuilder create --package cdk8s/dist/backstage-secrets --package cdk8s/dist/backstage
```

### 2. Verify Deployment

```bash
# Check ArgoCD applications
kubectl get applications -n argocd | grep backstage

# Expected output:
# backstage-secrets   Synced   Healthy
# backstage           Synced   Healthy
```

### 3. Verify External Secrets

```bash
# Check ExternalSecret status
kubectl get externalsecrets -n backstage

# Expected:
# backstage-oidc             SecretSynced
# gitea-credentials          SecretSynced
# ghcr-dockercfg-external    SecretSynced
# argocd-credentials         SecretSynced
```

### 4. Verify Backstage Deployment

```bash
# Check pods
kubectl get pods -n backstage

# Expected:
# backstage-xxx              1/1     Running
# postgresql-0               1/1     Running

# Check services
kubectl get svc -n backstage

# Expected:
# backstage     ClusterIP   ...   7007/TCP
# postgresql    ClusterIP   None  5432/TCP
```

### 5. Access Backstage UI

```bash
# Via ingress (default)
open https://cnoe.localtest.me:8443

# Or via port-forward
kubectl port-forward -n backstage svc/backstage 7007:7007
open http://localhost:7007
```

## Troubleshooting

### Chart Not Found

If synthesis fails with "Chart type not found":

```bash
# Verify chart is registered
cd cdk8s
npx ts-node -e "
  const { autoRegisterCharts } = require('./lib/auto-register-charts');
  const { IdpBuilderChartFactory } = require('./lib/idpbuilder-chart-factory');
  autoRegisterCharts();
  console.log(IdpBuilderChartFactory.getRegisteredTypes());
"
```

Should include: `BackstageChart`, `BackstageSecretsChart`

### Missing Resources

If resource count doesn't match:

```bash
# Check for synthesis errors
npm run synth 2>&1 | grep -i error

# Verify imports compile
npx tsc --noEmit
```

### External Secrets Not Syncing

If ExternalSecrets remain in `SecretSyncError`:

```bash
# Check ClusterSecretStore health
kubectl get clustersecretstores

# Check specific ExternalSecret
kubectl describe externalsecret -n backstage backstage-oidc
```

Common issues:
- Keycloak ClusterSecretStore not deployed
- Gitea ClusterSecretStore not deployed
- Azure Key Vault ClusterSecretStore missing GITHUB-PAT secret

### Deployment Failing

If Backstage pod fails to start:

```bash
# Check pod events
kubectl describe pod -n backstage -l app=backstage

# Check logs
kubectl logs -n backstage -l app=backstage --tail=50
```

Common issues:
- Image pull error → Check ghcr-dockercfg secret exists
- Database connection error → Check postgresql-0 is running
- Missing env vars → Check backstage-env-vars secret exists

## Success Criteria Validation

| Criterion | Validation Command | Expected |
|-----------|-------------------|----------|
| SC-001 | `idpbuilder create --package cdk8s/dist/backstage` | Deploys successfully |
| SC-002 | `ls dist/backstage*/manifests/*.yaml \| wc -l` | 21 files |
| SC-003 | `grep "kind:" dist/backstage/manifests/*.yaml` | 11 resources |
| SC-004 | `grep "kind:" dist/backstage-secrets/manifests/*.yaml` | 10 resources |
| SC-005 | `kubectl get app -n argocd backstage` | Healthy |
| SC-006 | `kubectl get es -n backstage -o jsonpath='{.items[*].status.conditions[0].type}'` | SecretSynced |
| SC-007 | `curl -k https://cnoe.localtest.me:8443` | 200 OK |

## Next Steps

After successful validation:

1. Enable in `config/applications.ts` (uncomment backstage entries)
2. Run full synthesis: `npm run synth`
3. Deploy to cluster: `idpbuilder create --package cdk8s/dist/`
4. Monitor ArgoCD for sync status
