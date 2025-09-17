# Troubleshooting Guide

## Table of Contents
- [Common Issues](#common-issues)
- [Image Pull Issues](#image-pull-issues)
- [Health Check Problems](#health-check-problems)
- [ArgoCD Sync Issues](#argocd-sync-issues)
- [VCluster Issues](#vcluster-issues)
- [Kargo Pipeline Issues](#kargo-pipeline-issues)
- [Secret Syncing Problems](#secret-syncing-problems)
- [Debugging Tools](#debugging-tools)
- [Recovery Procedures](#recovery-procedures)

## Common Issues

### Issue: Application Stuck in "Progressing" State

**Symptoms:**
- ArgoCD shows application as "Synced Progressing"
- Pods are running but not becoming ready
- Health checks may be failing

**Common Causes:**
1. Health check misconfiguration
2. Application startup issues
3. Missing dependencies (databases, secrets)
4. Resource constraints

**Resolution:**
```bash
# Check pod status
kubectl get pods -n <namespace> -o wide

# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace> --tail=50

# Check resource usage
kubectl top pod <pod-name> -n <namespace>
```

### Issue: "Unknown Healthy" Status in ArgoCD

**Symptoms:**
- Application shows as "Unknown Healthy" 
- Resources may actually be running fine

**Cause:**
- ArgoCD using `cnoe://` URLs that haven't been processed by IdpBuilder
- Application manifest source not properly configured

**Resolution:**
1. Ensure deployment uses IdpBuilder:
   ```bash
   idpbuilder create --package dist/<package-name>
   ```
2. Verify repository exists in Gitea
3. Force refresh in ArgoCD:
   ```bash
   argocd app get <app-name> --refresh
   ```

## Image Pull Issues

### Issue: ImagePullBackOff for Private Registry

**Case Study: Backstage Staging Image Pull Failure**

**Symptom:**
```
Failed to pull image "ghcr.io/pittampalliorg/backstage-cnoe:latest": 
failed to authorize: 401 Unauthorized
```

**Root Cause:**
- Missing imagePullSecrets in deployment
- GHCR requires authentication for private images

**Solution Implemented:**

1. **Create External Secret for GHCR credentials:**
```typescript
// charts/backstage-secrets-chart.ts
new ExternalSecret(this, 'ghcr-dockercfg-external', {
  metadata: {
    name: 'ghcr-dockercfg-external',
    namespace: 'backstage'
  },
  spec: {
    target: {
      name: 'ghcr-dockercfg',
      template: {
        type: 'kubernetes.io/dockerconfigjson',
        data: {
          '.dockerconfigjson': '{\n  "auths": {\n    "ghcr.io": {\n      "username": "pittampalliorg",\n      "password": "{{ .pat }}",\n      "auth": "{{ printf "%s:%s" "pittampalliorg" .pat | b64enc }}"\n    }\n  }\n}'
        }
      }
    },
    data: [{
      secretKey: 'pat',
      remoteRef: {
        key: 'GITHUB-PAT'
      }
    }]
  }
});
```

2. **Add imagePullSecrets to deployment:**
```typescript
// In deployment spec
spec: {
  imagePullSecrets: [
    { name: 'ghcr-dockercfg' }
  ]
}
```

3. **Ensure namespace exists on host for syncing:**
```bash
kubectl create namespace backstage
```

### Issue: Wrong Image Architecture

**Symptoms:**
- Pod crashes immediately after starting
- Error: "exec format error"

**Resolution:**
- Verify image architecture matches cluster nodes
- Build multi-arch images:
  ```dockerfile
  docker buildx build --platform linux/amd64,linux/arm64 -t image:tag .
  ```

## Health Check Problems

### Issue: Dev Environment Containers Restarting

**Case Study: Backstage Dev with sleep infinity**

**Symptom:**
- Dev containers using `sleep infinity` constantly restart
- Health checks fail causing "Degraded" status

**Root Cause:**
- Health probes configured for port 7007
- Container running `sleep infinity` doesn't listen on any port

**Solution:**
```typescript
// Conditional health checks based on environment
const healthProbes = envName !== 'dev' ? {
  livenessProbe: {
    httpGet: {
      path: '/healthcheck',
      port: k8s.IntOrString.fromNumber(7007)
    },
    initialDelaySeconds: 60,
    periodSeconds: 10
  },
  readinessProbe: {
    httpGet: {
      path: '/healthcheck',
      port: k8s.IntOrString.fromNumber(7007)
    },
    initialDelaySeconds: 30,
    periodSeconds: 10
  }
} : {};  // No health checks for dev

// Apply to container
containers: [{
  ...containerSpec,
  ...healthProbes
}]
```

### Issue: Port Mismatch in Health Checks

**Symptom:**
- Application running but health checks fail
- Logs show application listening on different port

**Example: RoadieHQ Backstage image**
- Image listens on port 7000
- Health checks configured for port 7007

**Resolution:**
```typescript
// Ensure health check port matches application port
const port = image.includes('roadiehq') ? 7000 : 7007;

livenessProbe: {
  httpGet: {
    path: '/healthcheck',
    port: k8s.IntOrString.fromNumber(port)
  }
}
```

## ArgoCD Sync Issues

### Issue: Application OutOfSync but Healthy

**Common with Kargo Pipelines Project**

**Symptom:**
```
kargo-pipelines-project OutOfSync Healthy
```

**Cause:**
- Missing required labels on namespace
- Kargo requires `kargo.akuity.io/project=true` label

**Resolution:**
```bash
# Apply required label
kubectl label namespace kargo-pipelines kargo.akuity.io/project=true

# Force sync
kubectl patch application kargo-pipelines-project -n argocd \
  --type merge -p '{"operation": {"initiatedBy": {"username": "admin"}, "sync": {"revision": "HEAD"}}}'
```

### Issue: Sync Failing with "Unknown Scheme"

**Symptom:**
```
error="unsupported scheme \"cnoe\""
```

**Cause:**
- Using `cnoe://` URLs without IdpBuilder processing
- Direct kubectl apply instead of IdpBuilder

**Resolution:**
```bash
# Must use IdpBuilder for cnoe:// URLs
idpbuilder create --package dist/

# Not: kubectl apply -f dist/
```

### Issue: Resources Not Syncing in Order

**Symptom:**
- Deployments fail because secrets don't exist
- Services created before deployments

**Resolution:**
Use sync-wave annotations:
```typescript
metadata: {
  annotations: {
    'argocd.argoproj.io/sync-wave': '-10'  // Negative = earlier
  }
}

// Typical ordering:
// -100: Namespaces
// -90: ServiceAccounts  
// -80: Secrets
// -70: ConfigMaps
// 0: Deployments
// 10: Services
// 20: Ingresses
```

## VCluster Issues

### Issue: Secrets Not Available in VCluster

**Symptom:**
- Pods in vcluster fail with "secret not found"
- Secret exists on host but not in vcluster

**Causes:**
1. Namespace doesn't exist on host
2. Sync mapping not configured
3. Secret created after vcluster

**Resolution:**

1. **Create namespace on host:**
```bash
kubectl create namespace backstage
```

2. **Verify sync configuration:**
```typescript
sync: {
  fromHost: {
    secrets: {
      enabled: true,
      mappings: {
        byName: {
          'backstage/*': 'backstage/*'
        }
      }
    }
  }
}
```

3. **Restart vcluster syncer:**
```bash
kubectl delete pod -n dev-vcluster vcluster-dev-helm-0
```

### Issue: Cannot Connect to VCluster

**Symptom:**
```
Unable to connect to the server: dial tcp: lookup dev-vcluster.cnoe.localtest.me
```

**Resolution:**

1. **Add to /etc/hosts:**
```
127.0.0.1 dev-vcluster.cnoe.localtest.me
127.0.0.1 staging-vcluster.cnoe.localtest.me
```

2. **Enable SSL passthrough in nginx:**
```yaml
controller:
  extraArgs:
    enable-ssl-passthrough: true
```

3. **For WSL2/Windows with port mapping:**
```bash
bash ref-implementation/setup-vcluster-kubeconfigs.sh
```

## Kargo Pipeline Issues

### Issue: Kargo Namespace Not Ready

**Symptom:**
- Cannot create Kargo resources
- "namespace is not a valid Kargo project" error

**Resolution:**
```bash
# Apply required label
kubectl label namespace kargo-pipelines kargo.akuity.io/project=true

# Create Project resource
kubectl apply -f - <<EOF
apiVersion: kargo.akuity.io/v1alpha1
kind: Project
metadata:
  name: kargo-pipelines
spec:
  promotionPolicies:
  - stage: dev
    autoPromotionEnabled: true
EOF
```

### Issue: Webhook Creation Failing

**Symptom:**
- Gitea webhooks not created
- Kargo not receiving repository events

**Resolution:**
Check webhook setup job:
```bash
# Check job status
kubectl get jobs -n kargo | grep webhook

# Check job logs
kubectl logs -n kargo job/gitea-webhook-setup

# Manually trigger job
kubectl delete job -n kargo gitea-webhook-setup
kubectl apply -f dist/kargo-gitea-webhook-setup.yaml
```

## Secret Syncing Problems

### Issue: External Secret Not Syncing

**Symptom:**
- ExternalSecret shows as "SecretSyncError"
- Secret not created from Azure Key Vault

**Common Causes:**
1. Azure authentication issues
2. Key Vault permissions
3. Secret name mismatch

**Debugging:**
```bash
# Check ExternalSecret status
kubectl get externalsecret -n <namespace> <name> -o yaml

# Check events
kubectl get events -n <namespace> | grep external

# Check External Secrets Operator logs
kubectl logs -n external-secrets deployment/external-secrets
```

**Resolution:**
1. Verify Workload Identity configuration
2. Check Key Vault access policies
3. Ensure secret exists in Key Vault with correct name

### Issue: Secret Format Incorrect

**Symptom:**
- Secret created but application can't use it
- Format doesn't match expected type

**Example: Docker config JSON**
```typescript
// Correct format for imagePullSecret
template: {
  type: 'kubernetes.io/dockerconfigjson',
  data: {
    '.dockerconfigjson': '{"auths": {...}}'
  }
}
```

## Debugging Tools

### Useful Commands

```bash
# Check application sync status
kubectl get applications -n argocd --no-headers | awk '{print $2, $3}' | sort | uniq -c

# Watch pod status
watch kubectl get pods -A | grep -v Running

# Follow logs
kubectl logs -f -n <namespace> <pod> --tail=100

# Check recent events
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Resource usage
kubectl top nodes
kubectl top pods -A | sort -k3 -rn | head -20

# Port forward to service
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Exec into pod
kubectl exec -it -n <namespace> <pod> -- /bin/bash

# Describe problematic resources
kubectl describe pod -n <namespace> <pod>
kubectl describe application -n argocd <app>
```

### ArgoCD CLI

```bash
# Login
argocd login localhost:8080 --grpc-web

# List applications
argocd app list

# Get application details
argocd app get <app-name>

# Sync application
argocd app sync <app-name>

# Hard refresh
argocd app get <app-name> --hard-refresh

# Check diff
argocd app diff <app-name>
```

## Recovery Procedures

### Complete Application Reset

When an application is completely broken:

```bash
# 1. Delete the application
kubectl delete application <app-name> -n argocd

# 2. Clean up resources
kubectl delete all -n <namespace> -l app=<app-name>

# 3. Regenerate manifests
cd /home/vpittamp/stacks/cdk8s
npm run synth

# 4. Reapply with IdpBuilder
idpbuilder create --package dist/<package-name>
```

### VCluster Recovery

If vcluster is corrupted:

```bash
# 1. Delete vcluster application
kubectl delete application vcluster-dev-helm -n argocd

# 2. Clean namespace
kubectl delete namespace dev-vcluster

# 3. Reapply
idpbuilder create --package dist/vcluster-dev
```

### Emergency Rollback

Quick rollback to previous version:

```bash
# 1. Get revision history
argocd app history <app-name>

# 2. Rollback to specific revision
argocd app rollback <app-name> <revision>

# 3. Or manually set image
kubectl set image deployment/<deployment> <container>=<image> -n <namespace>
```

## Prevention Best Practices

1. **Always Test Locally**: Use `npm run type-check` before synthesis
2. **Incremental Changes**: Deploy one application at a time
3. **Monitor Logs**: Set up log aggregation for easier debugging
4. **Resource Limits**: Always set appropriate limits
5. **Health Checks**: Configure appropriate for each environment
6. **Backup Configurations**: Keep backups of working configurations
7. **Document Changes**: Note any manual interventions

## Related Documentation

- [GitOps Architecture Overview](./gitops-architecture-overview.md)
- [VCluster Architecture](./vcluster-architecture.md)
- [Secrets Management](./secrets-management.md)
- [Development Workflow](./development-workflow.md)