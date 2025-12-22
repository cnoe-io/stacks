# Quickstart: Kargo Progressive Delivery Pipelines Framework

**Branch**: `105-setup-kargo-pipelines` | **Date**: 2025-12-11

## Prerequisites

- KIND cluster running with idpbuilder
- Kargo v1.8.x installed
- ArgoCD installed and operational
- External Secrets Operator with Azure Key Vault integration
- Tailscale for external webhook access (optional, for GitHub webhooks)

## Quick Deployment

```bash
# Navigate to CDK8s directory
cd cdk8s

# Synthesize manifests
npm run synth

# Deploy via idpbuilder
idpbuilder create --package dist/kargo-backstage-pipeline
```

## Validation Steps

### 1. Verify Project and ProjectConfig

```bash
# Check Project exists
kubectl get projects -n kargo-pipelines
# Expected: kargo-pipelines

# Check ProjectConfig
kubectl get projectconfigs -n kargo-pipelines
# Expected: kargo-pipelines

# Verify promotion policies
kubectl get projectconfig kargo-pipelines -n kargo-pipelines -o yaml | grep -A 20 promotionPolicies
```

### 2. Verify Warehouses

```bash
# List warehouses
kubectl get warehouses -n kargo-pipelines
# Expected:
# backstage-gitea   (Inner Loop)
# backstage-ghcr    (Outer Loop)

# Check warehouse status
kubectl describe warehouse backstage-gitea -n kargo-pipelines
kubectl describe warehouse backstage-ghcr -n kargo-pipelines
# Look for: "Discovered X images"
```

### 3. Verify Stages

```bash
# List stages
kubectl get stages -n kargo-pipelines
# Expected:
# backstage-local-dev  (Inner Loop)
# backstage-dev        (Outer Loop - dev)
# backstage-staging    (Outer Loop - staging)
# backstage-prod       (Outer Loop - production placeholder)

# Check stage status
kubectl get stages -n kargo-pipelines -o wide
# Look for: CurrentFreight, Health
```

### 4. Verify Webhook Configuration

```bash
# Get webhook endpoints
kubectl get projectconfig kargo-pipelines -n kargo-pipelines \
  -o jsonpath='{.status.webhookReceivers}' | jq .
# Expected: URLs for gitea-backstage and github-backstage receivers

# Verify webhook secrets exist
kubectl get secrets -n kargo-pipelines | grep webhook
# Expected:
# kargo-gitea-webhook-secret
# kargo-github-webhook-secret
```

## Test Inner Loop (Gitea)

### Step 1: Build and Push Image to Gitea

```bash
# Build Backstage image (from backstage source)
docker build -t backstage:dev-abc1234 .

# Tag for Gitea registry
docker tag backstage:dev-abc1234 \
  gitea.cnoe.localtest.me:8443/giteaadmin/backstage:dev-abc1234

# Get Gitea credentials
GITEA_PASSWORD=$(idpbuilder get secrets -p gitea -o json | jq -r '.[0].data.password')

# Login to Gitea registry
echo $GITEA_PASSWORD | docker login gitea.cnoe.localtest.me:8443 \
  -u giteaAdmin --password-stdin

# Push image
docker push gitea.cnoe.localtest.me:8443/giteaadmin/backstage:dev-abc1234
```

### Step 2: Verify Freight Creation

```bash
# Wait for Freight to appear (webhook: ~10s, polling: up to 5min)
kubectl get freights -n kargo-pipelines -w

# Check Freight details
kubectl get freights -n kargo-pipelines -o yaml | head -50
# Look for: images[].tag = dev-abc1234
```

### Step 3: Verify Auto-Promotion to local-dev

```bash
# Check promotions
kubectl get promotions -n kargo-pipelines
# Expected: Promotion to backstage-local-dev with status Succeeded

# Check stage current freight
kubectl get stage backstage-local-dev -n kargo-pipelines -o jsonpath='{.status.currentFreight}'

# Verify ArgoCD Application updated
kubectl get application backstage-local-dev -n argocd -o yaml | grep image
# Expected: image containing dev-abc1234
```

### Step 4: Verify Deployment

```bash
# Check Backstage deployment in KIND
kubectl get pods -n backstage-local-dev
# Expected: backstage pod running with new image

# Check pod image
kubectl get pod -n backstage-local-dev -l app=backstage \
  -o jsonpath='{.items[0].spec.containers[0].image}'
# Expected: gitea.cnoe.localtest.me:8443/giteaadmin/backstage:dev-abc1234
```

## Test Outer Loop (GitHub)

### Step 1: Trigger GitHub Actions (simulate)

For testing without actual CI:

```bash
# Tag image for GHCR (simulate CI build output)
docker tag backstage:dev-abc1234 \
  ghcr.io/pittampalliorg/backstage:v1.0.0

# Login to GHCR
echo $GITHUB_PAT | docker login ghcr.io -u pittampalliorg --password-stdin

# Push image
docker push ghcr.io/pittampalliorg/backstage:v1.0.0
```

### Step 2: Verify Freight Creation

```bash
# Wait for Freight from GHCR warehouse
kubectl get freights -n kargo-pipelines --selector origin=backstage-ghcr -w

# Check Freight details
kubectl describe freight -n kargo-pipelines | grep -A 10 "ghcr.io"
```

### Step 3: Verify Auto-Promotion to dev

```bash
# Check promotions to dev stage
kubectl get promotions -n kargo-pipelines --selector stage=backstage-dev

# Verify stage current freight
kubectl get stage backstage-dev -n kargo-pipelines -o jsonpath='{.status.currentFreight}'
```

### Step 4: Manual Promotion to Staging

```bash
# Get available Freight for staging
kubectl get freights -n kargo-pipelines \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | head -5

# Create manual promotion (replace FREIGHT_NAME)
cat <<EOF | kubectl apply -f -
apiVersion: kargo.akuity.io/v1alpha1
kind: Promotion
metadata:
  name: promote-to-staging-$(date +%s)
  namespace: kargo-pipelines
spec:
  stage: backstage-staging
  freight: FREIGHT_NAME
EOF

# Or use Kargo CLI
kargo promote --project kargo-pipelines \
  --stage backstage-staging \
  --freight FREIGHT_NAME
```

### Step 5: Verify Staging Promotion

```bash
# Check promotion status
kubectl get promotions -n kargo-pipelines --selector stage=backstage-staging

# Verify staging stage
kubectl get stage backstage-staging -n kargo-pipelines -o wide
```

## Kargo UI Verification

```bash
# Access Kargo UI (via Tailscale)
open "https://kargo-${CLUSTER_NAME:-<cluster>}.${TAILSCALE_TAILNET:-tail286401}.ts.net"

# Or port-forward
kubectl port-forward -n kargo svc/kargo-api 8080:443
open https://localhost:8080
```

### UI Navigation

1. **Project Selection**: Select `kargo-pipelines` from the project dropdown
2. **Pipeline View**: Both inner and outer loop pipelines are visible

### Distinguishing Inner vs Outer Loop

Resources are labeled with `kargo.akuity.io/loop` for visual grouping:

| Resource | Loop | Description |
|----------|------|-------------|
| `backstage-gitea` (Warehouse) | inner | Monitors Gitea OCI registry |
| `backstage-local-dev` (Stage) | inner | Local development deployment |
| `backstage-ghcr` (Warehouse) | outer | Monitors GHCR registry |
| `backstage-dev` (Stage) | outer | Development environment |
| `backstage-staging` (Stage) | outer | Staging (Talos) environment |
| `backstage-prod` (Stage) | outer | Production placeholder |

### Verify in UI

1. **Project `kargo-pipelines`** is visible in the project list
2. **Two Warehouses** are displayed:
   - `backstage-gitea` (inner loop) - shows Gitea images with `dev-*` tags
   - `backstage-ghcr` (outer loop) - shows GHCR images with semver tags
3. **Four Stages** are displayed:
   - `backstage-local-dev` → auto-promotes from `backstage-gitea`
   - `backstage-dev` → auto-promotes from `backstage-ghcr`
   - `backstage-staging` → manual promotion from `backstage-dev`
   - `backstage-prod` → manual promotion from `backstage-staging` (placeholder)
4. **Freight history** shows image versions and promotion history
5. **Stage progression** visualizes the flow from Warehouse → Stages

### Filtering by Loop Type

Use label selectors to filter resources:

```bash
# View only inner loop resources
kubectl get warehouses,stages -n kargo-pipelines -l kargo.akuity.io/loop=inner

# View only outer loop resources
kubectl get warehouses,stages -n kargo-pipelines -l kargo.akuity.io/loop=outer
```

## Troubleshooting

### Warehouse Not Discovering Images

```bash
# Check warehouse status
kubectl describe warehouse backstage-gitea -n kargo-pipelines

# Common issues:
# - insecureSkipTLSVerify not set for Gitea
# - allowTags pattern not matching pushed tags
# - Registry unreachable
```

### Freight Not Created After Push

```bash
# Check if webhook was received
kubectl logs -n kargo deploy/kargo-controller | grep webhook

# Verify webhook secret matches
kubectl get secret kargo-gitea-webhook-secret -n kargo-pipelines -o yaml

# Force warehouse refresh
kubectl annotate warehouse backstage-gitea -n kargo-pipelines \
  refresh=$(date +%s) --overwrite
```

### Promotion Failing

```bash
# Check promotion status
kubectl describe promotion <promotion-name> -n kargo-pipelines

# Check ArgoCD Application authorization annotation
kubectl get application backstage-local-dev -n argocd \
  -o jsonpath='{.metadata.annotations.kargo\.akuity\.io/authorized-stage}'
# Expected: kargo-pipelines:backstage-local-dev
```

### ArgoCD Not Syncing

```bash
# Check Application status
argocd app get backstage-local-dev --insecure

# Force sync
argocd app sync backstage-local-dev --prune --insecure

# Check sync errors
kubectl describe application backstage-local-dev -n argocd | grep -A 10 "Sync Status"
```

## Performance Benchmarks

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Inner Loop: Push → Freight | < 30s | Time from `docker push` to Freight creation |
| Inner Loop: Push → Running | < 60s | Time from `docker push` to pod ready |
| Outer Loop: Push → Freight | < 30s | Time from GHCR push to Freight creation |
| Outer Loop: Auto-promote | < 2min | Time from Freight to dev stage promotion |
| Manual Promotion | < 5min | Time from promotion request to deployment |

## Webhook Configuration

### Gitea Webhook Setup (Inner Loop)

Webhooks eliminate polling latency, enabling sub-30-second Freight creation.

#### Step 1: Get Webhook Receiver URL

```bash
# Get the webhook receiver URL for Gitea
kubectl get projectconfig kargo-pipelines -n kargo-pipelines \
  -o jsonpath='{.status.webhookReceivers[?(@.name=="gitea-backstage")].url}'

# Example output: https://kargo.cnoe.localtest.me:8443/webhooks/gitea-backstage
```

#### Step 2: Get Webhook Secret

```bash
# Get the webhook secret value
kubectl get secret kargo-gitea-webhook-secret -n kargo-pipelines \
  -o jsonpath='{.data.secret}' | base64 -d

# Or generate a new secure secret
NEW_SECRET=$(openssl rand -base64 48 | tr -d '=+/' | head -c 32)
echo "New webhook secret: $NEW_SECRET"

# Update the secret
kubectl patch secret kargo-gitea-webhook-secret -n kargo-pipelines \
  --type json \
  -p='[{"op": "replace", "path": "/stringData/secret", "value": "'$NEW_SECRET'"}]'
```

#### Step 3: Configure Gitea Webhook

1. Navigate to your Gitea repository: `https://gitea.cnoe.localtest.me:8443/giteaadmin/backstage/settings/hooks`
2. Click **Add Webhook** → **Gitea**
3. Configure:
   - **Target URL**: `<webhook receiver URL from step 1>`
   - **HTTP Method**: POST
   - **Content Type**: application/json
   - **Secret**: `<secret from step 2>`
   - **Trigger On**: Push Events (for OCI registry pushes, select "Package" if available)
   - **Active**: ✓ Checked

4. Click **Add Webhook**
5. Test the webhook using the **Test Delivery** button

### GitHub Webhook Setup (Outer Loop)

For CI-built images pushed to GHCR, GitHub webhooks notify Kargo instantly.

#### Prerequisites

- GitHub repository with Actions pushing to GHCR
- Tailscale or public ingress for external webhook access

#### Step 1: Get Webhook Receiver URL

```bash
# Get the webhook receiver URL for GitHub
kubectl get projectconfig kargo-pipelines -n kargo-pipelines \
  -o jsonpath='{.status.webhookReceivers[?(@.name=="github-backstage")].url}'

# For external access via Tailscale:
# https://kargo-<cluster>.<tailnet>.ts.net/webhooks/github-backstage
```

#### Step 2: Get Webhook Secret

```bash
# Get the webhook secret value
kubectl get secret kargo-github-webhook-secret -n kargo-pipelines \
  -o jsonpath='{.data.secret}' | base64 -d
```

#### Step 3: Configure GitHub Webhook

1. Navigate to your GitHub repository: `https://github.com/PittampalliOrg/backstage/settings/hooks`
2. Click **Add webhook**
3. Configure:
   - **Payload URL**: `<webhook receiver URL from step 1>`
   - **Content type**: application/json
   - **Secret**: `<secret from step 2>`
   - **SSL verification**: Enable (if using valid TLS cert)
   - **Events**: Select **Let me select individual events**
     - ✓ **Packages** (for GHCR registry events)
     - ✓ **Push** (optional, for Git-based triggers)
   - **Active**: ✓ Checked

4. Click **Add webhook**
5. GitHub will send a ping event - verify it succeeds

### External Access for GitHub Webhooks

GitHub requires HTTPS endpoints accessible from the internet.

#### Option 1: Tailscale Funnel (Recommended for Development)

```bash
# Expose Kargo API via Tailscale Funnel
# This is handled by the tailscale-serve chart for kargo

# Webhook URL will be:
# https://kargo-<cluster>.<tailnet>.ts.net/webhooks/github-backstage
```

#### Option 2: Ingress with TLS

```bash
# Verify Kargo ingress exists
kubectl get ingress -n kargo

# Ensure TLS is configured with valid certificate
# Webhook URL will be:
# https://kargo.<your-domain>/webhooks/github-backstage
```

### Verifying Webhook Delivery

```bash
# Watch for new Freight (should appear within 30s of push)
kubectl get freights -n kargo-pipelines -w

# Check Kargo controller logs for webhook events
kubectl logs -n kargo deploy/kargo-controller --tail=50 | grep -i webhook

# View webhook receiver status
kubectl get projectconfig kargo-pipelines -n kargo-pipelines \
  -o jsonpath='{.status.webhookReceivers}' | jq .
```

### Troubleshooting Webhooks

| Issue | Cause | Solution |
|-------|-------|----------|
| Webhook returns 401 | Secret mismatch | Verify secret in both Kargo and Git provider |
| Webhook returns 404 | Wrong URL | Check ProjectConfig status for correct URL |
| Webhook times out | Network issue | Verify Kargo API is accessible from Git provider |
| Freight not created | Wrong event type | Ensure "Package" or "Push" events are selected |
| SSL verification fails | Invalid cert | Use Tailscale (auto-TLS) or configure cert-manager |

## Developer Workflow: Inner Loop to Outer Loop

This section documents the developer workflow for transitioning from inner loop testing to outer loop production path.

### Image Tagging Strategy

| Loop | Registry | Tag Pattern | Example | Selection Strategy |
|------|----------|-------------|---------|-------------------|
| Inner | Gitea | `dev-<7-char-hex>` | `dev-abc1234` | Lexical (newest tag) |
| Outer | GHCR | Semantic Version | `v1.2.3` | SemVer (highest version) |

### Workflow Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Developer Workflow                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. INNER LOOP (Rapid Iteration)                                        │
│     ┌──────────┐    ┌─────────┐    ┌─────────────┐    ┌─────────────┐  │
│     │ Code     │───▶│ Build   │───▶│ Push to     │───▶│ Auto-deploy │  │
│     │ Change   │    │ Image   │    │ Gitea       │    │ local-dev   │  │
│     └──────────┘    └─────────┘    │ dev-abc1234 │    │ (KIND)      │  │
│                                     └─────────────┘    └─────────────┘  │
│     ↺ Repeat until feature is ready (< 60s per iteration)               │
│                                                                          │
│  2. CREATE PR                                                            │
│     ┌──────────┐    ┌─────────────┐                                     │
│     │ git push │───▶│ Open PR     │                                     │
│     │ branch   │    │ for review  │                                     │
│     └──────────┘    └─────────────┘                                     │
│                                                                          │
│  3. OUTER LOOP (CI-Verified)                                            │
│     ┌──────────┐    ┌─────────────┐    ┌─────────┐    ┌─────────────┐  │
│     │ PR       │───▶│ GitHub      │───▶│ Push to │───▶│ Auto-deploy │  │
│     │ Merged   │    │ Actions CI  │    │ GHCR    │    │ dev (KIND)  │  │
│     └──────────┘    └─────────────┘    │ v1.2.3  │    └─────────────┘  │
│                                         └─────────┘                      │
│                                                                          │
│  4. PROMOTION TO STAGING                                                 │
│     ┌─────────────┐    ┌─────────────┐    ┌─────────────────────────┐  │
│     │ Manual      │───▶│ Kargo       │───▶│ Deploy to staging       │  │
│     │ Promote     │    │ Promotion   │    │ (Talos cluster)         │  │
│     └─────────────┘    └─────────────┘    └─────────────────────────┘  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Step-by-Step Workflow

#### 1. Inner Loop Development

```bash
# Make code changes
cd ~/backstage
vim src/App.tsx

# Build and tag for inner loop
docker build -t backstage:dev-$(git rev-parse --short HEAD) .

# Push to Gitea (inner loop)
docker tag backstage:dev-$(git rev-parse --short HEAD) \
  gitea.cnoe.localtest.me:8443/giteaadmin/backstage:dev-$(git rev-parse --short HEAD)

GITEA_PASSWORD=$(idpbuilder get secrets -p gitea -o json | jq -r '.[0].data.password')
echo $GITEA_PASSWORD | docker login gitea.cnoe.localtest.me:8443 -u giteaAdmin --password-stdin

docker push gitea.cnoe.localtest.me:8443/giteaadmin/backstage:dev-$(git rev-parse --short HEAD)

# Verify deployment in local-dev (should be automatic within 60s)
kubectl get pods -n backstage-local-dev -w
```

#### 2. Create Pull Request

```bash
# Commit and push to feature branch
git add .
git commit -m "feat: add new feature"
git push origin feature/my-feature

# Open PR in GitHub
gh pr create --title "feat: add new feature" --body "Description of changes"
```

#### 3. Outer Loop (After PR Merge)

GitHub Actions will automatically:
1. Run tests and build the image
2. Tag with semantic version (e.g., `v1.2.3`)
3. Push to GHCR

```bash
# After merge, verify CI pushed image
gh run list --limit 5

# Verify Freight created from GHCR
kubectl get freights -n kargo-pipelines -l origin=backstage-ghcr

# Verify auto-promotion to dev
kubectl get promotions -n kargo-pipelines --selector stage=backstage-dev
```

#### 4. Promote to Staging

```bash
# Get available Freight for staging
kubectl get freights -n kargo-pipelines \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'

# Promote to staging (manual)
kargo promote --project kargo-pipelines \
  --stage backstage-staging \
  --freight <freight-name>

# Or via Kargo UI:
# 1. Open https://kargo-<cluster>.<tailnet>.ts.net
# 2. Select project: kargo-pipelines
# 3. Click on backstage-staging stage
# 4. Click "Promote" and select Freight
```

### CI Configuration Example

For GitHub Actions to push semver-tagged images:

```yaml
# .github/workflows/build.yml
name: Build and Push

on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract version
        id: version
        run: |
          if [[ $GITHUB_REF == refs/tags/v* ]]; then
            echo "version=${GITHUB_REF#refs/tags/}" >> $GITHUB_OUTPUT
          else
            echo "version=v0.0.0-$(git rev-parse --short HEAD)" >> $GITHUB_OUTPUT
          fi

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          push: true
          tags: |
            ghcr.io/${{ github.repository_owner }}/backstage:${{ steps.version.outputs.version }}
            ghcr.io/${{ github.repository_owner }}/backstage:latest
```

## Next Steps

After validation:
1. ~~Configure Gitea webhook (if not using polling only)~~ - See Webhook Configuration above
2. ~~Configure GitHub webhook for GHCR events~~ - See Webhook Configuration above
3. Add additional applications using the pipeline factory
4. Configure production stage when cluster is available
