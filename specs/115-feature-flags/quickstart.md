# Quickstart: Feature Flagging System

**Feature**: 115-feature-flags | **Date**: 2025-12-29

This guide covers deploying the feature flagging system and using feature flags in your applications.

---

## Prerequisites

- Kubernetes cluster (KIND or Talos) with ArgoCD
- External Secrets Operator configured
- Keycloak running with `cnoe` realm
- Tailscale operator (for remote access)
- OpenTelemetry collector (for observability)

---

## Deployment

### Step 1: Deploy Feature Flag Infrastructure

```bash
# Synthesize CDK8s charts
cd cdk8s
npm run synth

# Deploy via ArgoCD (automatic if using idpBuilder)
idpbuilder create --package dist/

# Or deploy specific apps:
kubectl apply -f dist/feature-flags-namespace.yaml
kubectl apply -f dist/feature-flags-secrets.yaml
kubectl apply -f dist/flagd.yaml
kubectl apply -f dist/flipt.yaml

# Wait for ArgoCD to sync
argocd app wait feature-flags-namespace --insecure
argocd app wait feature-flags-secrets --insecure
argocd app wait flagd --insecure
argocd app wait flipt --insecure
```

### Step 2: Verify Deployment

```bash
# Check pods are running
kubectl get pods -n feature-flags
# Expected output:
# NAME                     READY   STATUS    RESTARTS   AGE
# flagd-xxxxx              1/1     Running   0          2m
# flipt-xxxxx              1/1     Running   0          2m

# Check services
kubectl get svc -n feature-flags
# Expected output:
# NAME     TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)
# flagd    ClusterIP   10.x.x.x       <none>        8013/TCP,8016/TCP
# flipt    ClusterIP   10.x.x.x       <none>        8080/TCP

# Test flagd health
kubectl exec -it deploy/flagd -n feature-flags -- wget -qO- http://localhost:8015/healthz
# Expected: OK
```

### Step 3: Access Flipt UI

**Local (KIND)**:
```bash
# Port forward to access locally
kubectl port-forward svc/flipt 8080:8080 -n feature-flags

# Open in browser
open http://localhost:8080
```

**Remote (Tailscale)**:
```
https://flipt-{cluster}.ts.net
```

Log in with your Keycloak credentials.

---

## Creating Your First Feature Flag

### Via Flipt UI

1. Navigate to Flipt UI
2. Select namespace (e.g., `development`)
3. Click "Create Flag"
4. Fill in:
   - **Key**: `my-first-flag`
   - **Name**: `My First Flag`
   - **Type**: Boolean
   - **Default Variant**: `off`
5. Add variants:
   - `on` = `true`
   - `off` = `false`
6. Enable the flag
7. Save

### Via Git (GitOps)

Create a file in the `feature-flags` repository:

```yaml
# flags/development/my-flags.yaml
version: "1.0"
namespace: development

flags:
  - key: my-first-flag
    name: My First Flag
    type: BOOLEAN
    description: A simple feature toggle
    enabled: true
    defaultVariant: "off"
    variants:
      - key: "on"
        value: true
      - key: "off"
        value: false
```

Commit and push. Flipt will sync within 30 seconds.

### Via API

```bash
# Get auth token
TOKEN=$(curl -s -X POST \
  "https://keycloak.cnoe.localtest.me/realms/cnoe/protocol/openid-connect/token" \
  -d "client_id=flipt" \
  -d "client_secret=${FLIPT_CLIENT_SECRET}" \
  -d "grant_type=client_credentials" \
  | jq -r '.access_token')

# Create flag
curl -X POST "http://flipt.feature-flags.svc.cluster.local:8080/api/v1/namespaces/development/flags" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "my-first-flag",
    "name": "My First Flag",
    "type": "BOOLEAN_FLAG_TYPE",
    "enabled": true,
    "defaultVariantKey": "off"
  }'
```

---

## Using Feature Flags in Applications

### Go Application

```go
package main

import (
    "context"
    "log"

    "github.com/open-feature/go-sdk/pkg/openfeature"
    flagd "github.com/open-feature/go-sdk-contrib/providers/flagd/pkg/provider"
)

func main() {
    // Configure provider
    provider := flagd.NewProvider(
        flagd.WithHost("flagd.feature-flags.svc.cluster.local"),
        flagd.WithPort(8013),
    )
    openfeature.SetProvider(provider)

    // Get client
    client := openfeature.NewClient("my-service")

    // Evaluate flag
    ctx := context.Background()
    evalCtx := openfeature.NewEvaluationContext(
        "user-123",  // targetingKey
        map[string]interface{}{
            "email": "user@example.com",
            "tier":  "premium",
        },
    )

    enabled, err := client.BooleanValue(ctx, "my-first-flag", false, evalCtx)
    if err != nil {
        log.Printf("Error evaluating flag: %v", err)
        return
    }

    if enabled {
        log.Println("Feature is enabled!")
    } else {
        log.Println("Feature is disabled")
    }
}
```

**Dependencies**:
```bash
go get github.com/open-feature/go-sdk
go get github.com/open-feature/go-sdk-contrib/providers/flagd
```

### TypeScript/Node.js Application

```typescript
import { OpenFeature, EvaluationContext } from '@openfeature/server-sdk';
import { FlagdProvider } from '@openfeature/flagd-provider';

async function main() {
  // Configure provider
  const provider = new FlagdProvider({
    host: 'flagd.feature-flags.svc.cluster.local',
    port: 8013,
    tls: false,
  });

  await OpenFeature.setProviderAndWait(provider);

  // Get client
  const client = OpenFeature.getClient('my-service');

  // Evaluation context
  const context: EvaluationContext = {
    targetingKey: 'user-123',
    email: 'user@example.com',
    tier: 'premium',
  };

  // Evaluate flag
  const enabled = await client.getBooleanValue('my-first-flag', false, context);

  if (enabled) {
    console.log('Feature is enabled!');
  } else {
    console.log('Feature is disabled');
  }
}

main();
```

**Dependencies**:
```bash
npm install @openfeature/server-sdk @openfeature/flagd-provider
```

### Python Application

```python
from openfeature import api
from openfeature.contrib.provider.flagd import FlagdProvider

# Configure provider
api.set_provider(FlagdProvider(
    host="flagd.feature-flags.svc.cluster.local",
    port=8013,
    tls=False,
))

# Get client
client = api.get_client("my-service")

# Evaluate flag
enabled = client.get_boolean_value(
    flag_key="my-first-flag",
    default_value=False,
    evaluation_context={
        "targetingKey": "user-123",
        "email": "user@example.com",
        "tier": "premium",
    },
)

if enabled:
    print("Feature is enabled!")
else:
    print("Feature is disabled")
```

**Dependencies**:
```bash
pip install openfeature-sdk openfeature-provider-flagd
```

### Browser/React Application (OFREP)

```typescript
import { OpenFeature } from '@openfeature/react-sdk';
import { OFREPWebProvider } from '@openfeature/ofrep-web-provider';

// Configure provider (browser uses OFREP HTTP)
const provider = new OFREPWebProvider({
  baseUrl: 'http://flagd.feature-flags.svc.cluster.local:8016',
  pollInterval: 30000, // Refresh every 30s
});

await OpenFeature.setProviderAndWait(provider);

// React hook usage
import { useBooleanFlagValue } from '@openfeature/react-sdk';

function MyComponent() {
  const darkMode = useBooleanFlagValue('dark-mode-enabled', false);

  return (
    <div className={darkMode ? 'dark' : 'light'}>
      {darkMode ? 'Dark Mode' : 'Light Mode'}
    </div>
  );
}
```

---

## Adding Targeting Rules

### Percentage Rollout (Gradual Release)

```yaml
flags:
  - key: new-feature
    name: New Feature
    type: BOOLEAN
    enabled: true
    defaultVariant: "off"
    variants:
      - key: "on"
        value: true
      - key: "off"
        value: false
    rules:
      # 10% of users get the feature
      - rank: 0
        distributions:
          - variant: "on"
            rollout: 10
          - variant: "off"
            rollout: 90
```

### User Segment Targeting

```yaml
segments:
  - key: beta-users
    name: Beta Users
    matchType: ANY
    constraints:
      - property: groups
        operator: IS_ONE_OF
        value: "beta-testers"
      - property: email
        operator: ENDS_WITH
        value: "@beta.company.com"

flags:
  - key: experimental-feature
    name: Experimental Feature
    type: BOOLEAN
    enabled: true
    defaultVariant: "off"
    variants:
      - key: "on"
        value: true
      - key: "off"
        value: false
    rules:
      # Beta users always get the feature
      - segment: beta-users
        rank: 0
        distributions:
          - variant: "on"
            rollout: 100
      # Everyone else gets default (off)
```

### Multi-Variant A/B Test

```yaml
flags:
  - key: button-color
    name: Button Color Test
    type: STRING
    enabled: true
    defaultVariant: blue
    variants:
      - key: blue
        value: "#0066CC"
      - key: green
        value: "#00CC66"
      - key: red
        value: "#CC0000"
    rules:
      - rank: 0
        distributions:
          - variant: blue
            rollout: 34
          - variant: green
            rollout: 33
          - variant: red
            rollout: 33
```

---

## Monitoring & Observability

### Grafana Dashboard

Access flag evaluation metrics at:
```
https://grafana.cnoe.localtest.me/d/feature-flags
```

**Key Metrics**:
- `flagd_evaluation_total` - Total evaluations by flag
- `flagd_evaluation_duration_seconds` - Evaluation latency
- `flagd_evaluation_errors_total` - Errors by flag

### OpenTelemetry Tracing

Flag evaluations are automatically traced. View in Jaeger:
```
https://jaeger.cnoe.localtest.me
```

Search for service `my-service` and operation `feature_flag.evaluation`.

---

## Troubleshooting

### Flag Not Evaluating

```bash
# Check flagd logs
kubectl logs -l app=flagd -n feature-flags

# Verify flag exists
kubectl exec -it deploy/flagd -n feature-flags -- \
  wget -qO- "http://localhost:8016/ofrep/v1/evaluate/flags/my-first-flag" \
  --post-data '{"context":{"targetingKey":"test"}}' \
  --header 'Content-Type: application/json'
```

### Sync Issues

```bash
# Check Flipt sync status
kubectl logs -l app=flipt -n feature-flags | grep sync

# Force sync restart
kubectl rollout restart deploy/flipt -n feature-flags
```

### SDK Connection Errors

```bash
# Test gRPC connectivity
kubectl run grpcurl --rm -it --image=fullstorydev/grpcurl --restart=Never -- \
  -plaintext flagd.feature-flags.svc.cluster.local:8013 list

# Test OFREP connectivity
kubectl run curl --rm -it --image=curlimages/curl --restart=Never -- \
  curl -s http://flagd.feature-flags.svc.cluster.local:8016/healthz
```

---

## GitOps Workflow

### Setting Up the Feature Flags Repository

1. **Create the Git repository** in Gitea:

```bash
# Create repo via Gitea API or UI
# Repository: giteaadmin/feature-flags

# Clone locally
git clone https://gitea.cnoe.localtest.me:8443/giteaadmin/feature-flags.git
cd feature-flags
```

2. **Initialize repository structure**:

```bash
mkdir -p flags/{development,staging,production}

# Create Flipt configuration
cat > .flipt.yml << 'EOF'
version: "1.0"
# Flipt reads flags from the flags/ directory
# Each subdirectory represents a namespace/environment
storage:
  type: object
  object:
    type: local
    local:
      path: flags/
EOF

# Create default namespace configuration
cat > flags/default.yaml << 'EOF'
version: "1.0"
namespace: default

flags: []
segments: []
EOF
```

3. **Create environment-specific flag files**:

```yaml
# flags/development/features.yaml
version: "1.0"
namespace: development

segments:
  - key: beta-users
    name: Beta Program Users
    matchType: ANY
    constraints:
      - property: groups
        operator: IS_ONE_OF
        value: "beta-testers,early-adopters"

flags:
  - key: dark-mode
    name: Dark Mode
    type: BOOLEAN_FLAG_TYPE
    enabled: true
    defaultVariant: "off"
    variants:
      - key: "on"
        value: true
      - key: "off"
        value: false
    rules:
      - segment: beta-users
        rank: 0
        distributions:
          - variant: "on"
            rollout: 100
```

4. **Commit and push**:

```bash
git add .
git commit -m "Initialize feature flags repository"
git push origin main
```

### PR-Based Flag Management Workflow

1. **Create a branch for flag changes**:

```bash
git checkout -b feature/enable-new-ui
```

2. **Edit flag configuration**:

```yaml
# flags/development/ui-features.yaml
version: "1.0"
namespace: development

flags:
  - key: new-dashboard-ui
    name: New Dashboard UI
    type: BOOLEAN_FLAG_TYPE
    enabled: true
    defaultVariant: "off"
    variants:
      - key: "on"
        value: true
      - key: "off"
        value: false
    rules:
      # 10% rollout to all users
      - rank: 0
        distributions:
          - variant: "on"
            rollout: 10
          - variant: "off"
            rollout: 90
```

3. **Create PR and merge**:

```bash
git add .
git commit -m "Enable new dashboard UI with 10% rollout"
git push origin feature/enable-new-ui

# Create PR via Gitea UI
# After review, merge to main
```

4. **Flipt automatically syncs** within 30 seconds of merge.

### Environment Promotion

Promote flags through environments by copying configurations:

```bash
# After testing in development
cp flags/development/ui-features.yaml flags/staging/ui-features.yaml

# Edit staging config to increase rollout
# Then commit and push

# After staging validation
cp flags/staging/ui-features.yaml flags/production/ui-features.yaml

# Edit production config for gradual rollout
```

### Flag Naming Conventions

| Pattern | Example | Use Case |
|---------|---------|----------|
| `{feature}-{state}` | `dark-mode-enabled` | Simple on/off toggles |
| `{service}-{feature}` | `api-rate-limit` | Service-specific flags |
| `{experiment}-{variant}` | `checkout-flow-v2` | A/B testing |
| `{release}-{feature}` | `2024-q1-new-nav` | Release flags |

---

## Next Steps

1. **Add flags for your services**: Start with simple boolean flags
2. **Set up targeting**: Create segments for beta users, premium tiers
3. **Configure GitOps**: Set up the `feature-flags` repository
4. **Add monitoring**: Create Grafana dashboards for flag usage
5. **Integrate with CI/CD**: Use flags to control rollouts

---

## Reference

- [flagd Documentation](https://flagd.dev/)
- [Flipt Documentation](https://docs.flipt.io/)
- [OpenFeature Specification](https://openfeature.dev/specification/)
- [SDK Documentation](https://openfeature.dev/docs/reference/technologies/)
