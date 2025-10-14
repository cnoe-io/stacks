# Remote Kubernetes Cluster Access via Tailscale

**Feature**: 005-remote-kubernetes-cluster
**Status**: Implementation in progress

## Overview

This guide explains how to securely access your Kubernetes cluster remotely using Tailscale's API server proxy. You'll be able to:

1. **kubectl Access**: Run kubectl commands from any Tailscale-connected device with <2 second response times
2. **Port Forwarding**: Access pod services locally via `kubectl port-forward`
3. **Web UI Access**: View cluster dashboards (ArgoCD, Gitea) from your browser

## Architecture

### Certificate Flow

```
┌─────────────────┐                    ┌──────────────────────┐                    ┌─────────────────┐
│  kubectl client │ ───TLS (Let's───▶  │ Tailscale Operator   │ ───TLS (Cluster──▶ │  Kubernetes API │
│  (Mac/Laptop)   │    Encrypt)        │  (In-process proxy)  │     CA)            │     Server      │
└─────────────────┘                    └──────────────────────┘                    └─────────────────┘
      │                                         │                                          │
      │ Resolves:                               │ Listens on:                              │ Listens on:
      │ kind-operator.tail286401.ts.net         │ 100.x.x.x:443                            │ 10.96.0.1:443
      │ → 100.x.x.x (Tailscale IP)              │ (Tailscale IP)                           │ (Cluster IP)
```

### Two-Layer TLS Validation

1. **External Layer** (kubectl → operator):
   - Validates certificate for `kind-operator.tail286401.ts.net`
   - Options: Tailscale HTTPS (Let's Encrypt) or cluster CA distribution
   - This is where certificate issues typically occur

2. **Internal Layer** (operator → API server):
   - Uses cluster CA certificate (automatic via ServiceAccount)
   - No user configuration needed

## Prerequisites

Before setting up remote access, ensure you have:

### Tailscale Prerequisites

1. **MagicDNS Enabled** (Required)
   - Login to [Tailscale Admin Console](https://login.tailscale.com/admin/dns)
   - Navigate to DNS settings
   - Verify "MagicDNS" is enabled
   - If disabled, click "Enable MagicDNS"

2. **HTTPS Certificates Enabled** (Recommended - Primary Method)
   - In Tailscale Admin Console → DNS → HTTPS Certificates
   - Click "Enable HTTPS"
   - This enables automatic Let's Encrypt certificate provisioning
   - **Important**: This is an org-level setting requiring admin access

3. **Tailscale Connected**
   - Tailscale client installed on your device
   - Authenticated to your organization's tailnet
   - Verify connectivity: `ping kind-operator.tail286401.ts.net` (replace with your operator hostname)

### Local Prerequisites

1. **kubectl Installed**
   - Version 1.27 or higher
   - Check version: `kubectl version --client`

2. **Cluster Access**
   - Local kubectl configured for cluster access
   - Used to extract client certificates for remote kubeconfig

### Cluster Prerequisites

1. **Tailscale Operator Deployed**
   - Deployed via ArgoCD with `APISERVER_PROXY=true`
   - OAuth credentials synced from Azure Key Vault
   - Verify: `kubectl get pods -n tailscale -l app=tailscale-operator`

2. **External Secrets Operator**
   - Running and configured for Azure Key Vault
   - Syncing TAILSCALE-OAUTH-CLIENT-ID and TAILSCALE-OAUTH-CLIENT-SECRET

## Certificate Provisioning: First Connection Delay

**⚠️ IMPORTANT**: When using Tailscale HTTPS, the first connection to the cluster will take **30-60 seconds** while the operator provisions a Let's Encrypt certificate for its MagicDNS hostname.

### What Happens

1. You run `kubectl get nodes` for the first time
2. kubectl connects to `kind-operator.tail286401.ts.net:443`
3. Tailscale operator initiates Let's Encrypt DNS challenge
4. Certificate is provisioned and cached (may take 30-60 seconds)
5. Connection completes successfully
6. **Subsequent connections are fast** (<2 seconds)

### Handling the Delay

When testing for the first time, increase the kubectl timeout:

```bash
# First connection (wait for certificate provisioning)
kubectl --kubeconfig=remote-kubeconfig.yaml get nodes --request-timeout=60s

# Subsequent connections (normal timeout)
kubectl --kubeconfig=remote-kubeconfig.yaml get nodes
```

## kubectl Access Setup

### Step 1: Generate Remote Kubeconfig

On the **cluster host** (machine with local kubectl access):

```bash
cd /path/to/stacks
./deployment/scripts/tailscale/generate-kubeconfig.sh
```

This generates `remote-kubeconfig.yaml` in the current directory with:
- Tailscale operator endpoint (`https://kind-operator.tail286401.ts.net:443`)
- Client certificates extracted from local kubeconfig
- No cluster CA certificate (uses Let's Encrypt via Tailscale HTTPS)

**Custom cluster/tailnet names:**

```bash
./deployment/scripts/tailscale/generate-kubeconfig.sh my-cluster tail123456
```

### Step 2: Copy to Remote Machine

Copy the generated kubeconfig to your remote machine (Mac, laptop, etc.):

```bash
# Via scp
scp remote-kubeconfig.yaml remote-machine:~/remote-kubeconfig.yaml

# Or copy the file contents and paste into a file on remote machine
cat remote-kubeconfig.yaml
# Copy output, then on remote machine:
cat > ~/remote-kubeconfig.yaml
# Paste contents, press Ctrl+D
```

### Step 3: Test kubectl Connectivity

On your **remote machine** (Mac/laptop):

```bash
# First connection (allow time for certificate provisioning)
kubectl --kubeconfig=~/remote-kubeconfig.yaml get nodes --request-timeout=60s

# Expected output (after 30-60 seconds):
# NAME                     STATUS   ROLES           AGE   VERSION
# localdev-control-plane   Ready    control-plane   5d    v1.33.1

# Verify subsequent commands are fast (<2 seconds)
kubectl --kubeconfig=~/remote-kubeconfig.yaml get pods -A

# Test authentication
kubectl --kubeconfig=~/remote-kubeconfig.yaml auth whoami
```

### Step 4: (Optional) Set as Default Kubeconfig

To avoid specifying `--kubeconfig` on every command:

```bash
# Temporary (current terminal session)
export KUBECONFIG=~/remote-kubeconfig.yaml

# Persistent (add to ~/.bashrc or ~/.zshrc)
echo 'export KUBECONFIG=~/remote-kubeconfig.yaml' >> ~/.bashrc
source ~/.bashrc
```

Or merge with existing kubeconfig:

```bash
# Backup existing kubeconfig
cp ~/.kube/config ~/.kube/config.backup

# Merge contexts
KUBECONFIG=~/.kube/config:~/remote-kubeconfig.yaml kubectl config view --flatten > ~/.kube/config.new
mv ~/.kube/config.new ~/.kube/config

# Switch to Tailscale context
kubectl config use-context kind-tailscale
```

## Troubleshooting

### `--insecure-skip-tls-verify`: Temporary Testing Only

The `--insecure-skip-tls-verify` flag **disables all TLS certificate validation** and should **ONLY** be used for temporary troubleshooting.

#### When to Use (Testing Only)

```bash
# Quick connectivity test (10 minutes maximum)
kubectl --kubeconfig=~/remote-kubeconfig.yaml get nodes --insecure-skip-tls-verify
```

✅ **Acceptable uses** (non-production, time-limited):
- Initial connectivity verification (verify network path works)
- Isolating certificate issues from connectivity issues
- Troubleshooting Tailscale HTTPS provisioning delays

❌ **Never use for**:
- Production clusters
- Environments with sensitive data
- Daily operations
- Automated scripts or CI/CD
- Anything longer than 10 minutes

#### Security Implications

When you use `--insecure-skip-tls-verify`:
- **Man-in-the-middle attacks possible**: Attacker can intercept and modify traffic
- **Certificate spoofing**: Fake certificates accepted as valid
- **Identity spoofing**: Attacker can impersonate the API server
- **No encryption guarantees**: Unable to verify TLS connection integrity

#### Proper Solutions

After verifying connectivity with `--insecure-skip-tls-verify`, implement proper certificate handling:

1. **Tailscale HTTPS** (Recommended for teams)
   - Enable HTTPS in Tailscale admin console
   - Wait for certificate provisioning (30-60 seconds first connection)
   - Automatic renewal, works across all operating systems

2. **Cluster CA Distribution** (For environments without Tailscale HTTPS)
   - See "Cluster CA Distribution Alternative" section below
   - Export cluster CA, distribute to user trust stores
   - Works with free Tailscale plans, no external dependencies

### Certificate Validation Errors

#### Error: `x509: certificate is valid for 10.96.0.1, not 100.x.x.x`

**Cause**: Connecting to Tailscale IP with cluster CA validation (cluster CA doesn't include Tailscale IPs in SAN)

**Solution 1** (Recommended): Enable Tailscale HTTPS
- Verify HTTPS enabled in Tailscale admin console
- Wait 30-60 seconds on first connection for certificate provisioning
- Confirm `remote-kubeconfig.yaml` does NOT include `certificate-authority` or `certificate-authority-data` fields

**Solution 2**: Use cluster CA distribution (see section below)

#### Error: `certificate signed by unknown authority`

**Cause**: Using cluster CA distribution but CA not in trust store

**Solution**: Add cluster CA to trust store (see "Cluster CA Distribution Alternative" section)

### TLS Handshake Timeout

**Error**: `TLS handshake timeout` on first connection

**Cause**: Certificate provisioning in progress (Tailscale HTTPS Let's Encrypt)

**Solution**:
```bash
# Increase timeout and wait
kubectl --kubeconfig=~/remote-kubeconfig.yaml get nodes --request-timeout=90s

# If still failing after 90 seconds, check operator status
kubectl get pods -n tailscale
kubectl logs -n tailscale deployment/tailscale-operator --tail=100
```

Look for log messages about certificate provisioning.

### Connection Refused / EOF

**Error**: `EOF` or `unable to connect to server: EOF`

**Cause**: Tailscale operator not running or APISERVER_PROXY not enabled

**Solution**:
```bash
# Check operator pod status
kubectl get pods -n tailscale -l app=tailscale-operator
# Should show: Running

# Check operator logs for API proxy startup
kubectl logs -n tailscale deployment/tailscale-operator --tail=50 | grep -i "proxy"
# Should show: "API server proxy listening on :443"

# Verify APISERVER_PROXY environment variable
kubectl get deployment -n tailscale tailscale-operator -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="APISERVER_PROXY")].value}'
# Should show: true
```

### Unauthorized Errors

**Error**: `Unauthorized` or `User "..." cannot list resource "nodes"`

**Cause**: Client certificates invalid or RBAC not configured

**Solution**:
```bash
# Verify client certificate validity
kubectl --kubeconfig=~/remote-kubeconfig.yaml config view --raw -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -d | openssl x509 -text -noout

# Check certificate expiration (look for "Not After" date)

# Test authentication (should show your user identity)
kubectl --kubeconfig=~/remote-kubeconfig.yaml auth whoami
```

If certificates are valid but still unauthorized, check RBAC configuration in cluster.

### Tailscale Connectivity Issues

**Error**: Cannot resolve `kind-operator.tail286401.ts.net`

**Solution**:
```bash
# Verify Tailscale is running
tailscale status

# Verify MagicDNS is working
dig kind-operator.tail286401.ts.net
# Should resolve to 100.x.x.x (Tailscale IP)

# Test direct connectivity
ping kind-operator.tail286401.ts.net

# Check Tailscale connection status
tailscale ping kind-operator
```

## Cluster CA Distribution Alternative

For environments **without Tailscale HTTPS** (free plans, air-gapped, CI/CD), you can distribute the cluster CA certificate instead.

### When to Use

- Tailscale HTTPS not available (organizational policy or plan limitations)
- CI/CD pipelines requiring predictable certificate paths
- Air-gapped environments
- Small teams (2-4 users) where manual distribution is acceptable

### Export Cluster CA

On the cluster host:

```bash
./deployment/scripts/tailscale/export-cluster-ca.sh

# Or manually:
docker exec localdev-control-plane cat /etc/kubernetes/pki/ca.crt > kind-ca.crt
```

### Install CA Certificate

#### macOS (OS-level trust store)

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain kind-ca.crt
```

**Note**: Requires admin privileges

#### Linux (OS-level trust store)

```bash
sudo cp kind-ca.crt /usr/local/share/ca-certificates/kind-cluster-ca.crt
sudo update-ca-certificates
```

#### kubectl-only (no OS changes)

```bash
# Copy CA file to a permanent location
cp kind-ca.crt ~/.kube/kind-ca.crt

# Update kubeconfig to reference CA file
kubectl config set-cluster kind-tailscale \
  --server=https://kind-operator.tail286401.ts.net:443 \
  --certificate-authority=$HOME/.kube/kind-ca.crt
```

**Important**: File path must remain valid. If you move or delete `kind-ca.crt`, kubectl will fail.

### Kubeconfig with Cluster CA

When using cluster CA distribution, your kubeconfig includes the `certificate-authority` field:

```yaml
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority: /Users/username/.kube/kind-ca.crt
    server: https://kind-operator.tail286401.ts.net:443
  name: kind-tailscale
# ... rest of config
```

Or embed the CA data directly (portable across machines):

```yaml
clusters:
- cluster:
    certificate-authority-data: LS0tLS1CRUdJTi... (base64-encoded CA cert)
    server: https://kind-operator.tail286401.ts.net:443
  name: kind-tailscale
```

## Port Forwarding Usage

kubectl port-forward allows you to access individual pod or service ports from your local machine, tunneling through the Tailscale connection to the cluster.

### Basic Port-Forward Syntax

```bash
# Forward to a pod
kubectl --kubeconfig=~/remote-kubeconfig.yaml port-forward pod/<pod-name> <local-port>:<remote-port>

# Forward to a service (recommended - handles pod restarts)
kubectl --kubeconfig=~/remote-kubeconfig.yaml port-forward -n <namespace> svc/<service-name> <local-port>:<remote-port>

# Forward multiple ports
kubectl --kubeconfig=~/remote-kubeconfig.yaml port-forward -n <namespace> svc/<service-name> <port1>:<port1> <port2>:<port2>

# Run in background
kubectl --kubeconfig=~/remote-kubeconfig.yaml port-forward -n <namespace> svc/<service-name> <local-port>:<remote-port> &
```

### Common Services to Forward

#### ArgoCD (HTTPS)

```bash
kubectl --kubeconfig=~/remote-kubeconfig.yaml port-forward -n argocd svc/argocd-server 8080:443 &
# Access at: https://localhost:8080
```

#### Gitea (HTTP)

```bash
kubectl --kubeconfig=~/remote-kubeconfig.yaml port-forward -n gitea svc/gitea-http 8081:3000 &
# Access at: http://localhost:8081
```

#### MinIO (S3-compatible storage)

```bash
kubectl --kubeconfig=~/remote-kubeconfig.yaml port-forward -n nix-cache svc/minio 8082:9000 &
# Access at: http://localhost:8082
# Console: http://localhost:8082/console
```

#### Postgres Database

```bash
kubectl --kubeconfig=~/remote-kubeconfig.yaml port-forward -n postgres svc/postgresql 5432:5432 &
# Connect: psql -h localhost -p 5432 -U <username>
```

#### Redis

```bash
kubectl --kubeconfig=~/remote-kubeconfig.yaml port-forward -n redis svc/redis 6379:6379 &
# Connect: redis-cli -h localhost -p 6379
```

### Automated Testing Script

Use the provided test script to validate port-forwarding:

```bash
cd /path/to/stacks
./deployment/scripts/tailscale/test-port-forward.sh ~/remote-kubeconfig.yaml
```

This script:
- Tests port-forwards to ArgoCD, Gitea, and MinIO
- Validates connectivity with curl
- Measures latency (should be <500ms added overhead)
- Provides cleanup instructions

### Multiple Simultaneous Port-Forwards

You can run multiple port-forwards simultaneously:

```bash
# Start multiple forwards in background
kubectl --kubeconfig=~/remote-kubeconfig.yaml port-forward -n argocd svc/argocd-server 8080:443 > /tmp/pf-argocd.log 2>&1 &
kubectl --kubeconfig=~/remote-kubeconfig.yaml port-forward -n gitea svc/gitea-http 8081:3000 > /tmp/pf-gitea.log 2>&1 &
kubectl --kubeconfig=~/remote-kubeconfig.yaml port-forward -n postgres svc/postgresql 5432:5432 > /tmp/pf-postgres.log 2>&1 &

# List background jobs
jobs

# Bring specific job to foreground
fg %1

# Kill specific background job
kill %2
```

### Port-Forward Stability

Port-forwards are generally stable but may need to be restarted if:
- The target pod is restarted or rescheduled
- Network connectivity is interrupted
- The kubectl process is terminated

**Best Practices**:
1. **Use services instead of pods**: Services handle pod restarts automatically
2. **Log output to files**: Redirect stdout/stderr when running in background
3. **Use process managers**: Consider using `systemd` or `supervisor` for critical forwards
4. **Monitor connectivity**: Check logs periodically for disconnections

### Debugging Port-Forward Issues

#### Port Already in Use

```bash
# Error: bind: address already in use
# Solution: Choose a different local port or kill the existing process
lsof -ti:8080 | xargs kill -9
```

#### Connection Refused

```bash
# Error: unable to do port forwarding: socat not found
# Solution: Install socat (usually available in base images)

# Error: unable to listen on port: Listeners failed to create with the following errors
# Solution: Check if service exists and is accessible
kubectl --kubeconfig=~/remote-kubeconfig.yaml get svc -n <namespace>
```

#### Frequent Disconnections

```bash
# Check kubectl logs
kubectl --kubeconfig=~/remote-kubeconfig.yaml port-forward -v=6 -n <namespace> svc/<service> <port>

# Verify Tailscale connectivity
ping kind-operator-13.tail286401.ts.net
```

### Performance Considerations

Port-forward adds minimal latency over direct Tailscale access:
- **Expected overhead**: <100ms for small requests
- **Large file transfers**: May see higher latency due to kubectl proxying
- **Concurrent connections**: Multiple port-forwards don't significantly impact performance

**Latency Breakdown**:
1. Local machine → Tailscale operator: ~10-50ms (Tailscale network)
2. Operator → Kubernetes API server: <1ms (in-cluster)
3. API server → Target pod: <1ms (in-cluster)
4. kubectl overhead: ~10-50ms (serialization/proxying)

**Total typical latency**: 20-100ms added to service response time

## Web UI Access

Access cluster web UIs (ArgoCD, Gitea, Backstage) directly from your browser on any Tailscale-connected device. This works because ingress-nginx is exposed via the kind host network, which is accessible over Tailscale.

### Architecture

```
Browser → Tailscale Network → Kind Host (Hetzner) → ingress-nginx → Service → Pod
                                    ↓
                            Port 8443 (HTTPS)
                            Port 80 (HTTP redirect)
```

**Key Points**:
- `*.cnoe.localtest.me` resolves to `127.0.0.1` externally (public DNS)
- Kind cluster binds ingress-nginx to host ports (80, 443, 8443)
- Tailscale provides access to the kind host's network interfaces
- DNS resolution happens locally, then traffic routes over Tailscale

### DNS Resolution Requirements

**External (from Mac/remote)**: `*.cnoe.localtest.me` → `127.0.0.1`
- This is the public localtest.me behavior
- NOT accessible directly (127.0.0.1 is localhost)
- BUT kind host is accessible via Tailscale, so we access via kind host's Tailscale IP

**Wait, how does this work?**

Actually, for web UI access from a remote Tailscale machine, you have two options:

#### Option 1: Port-Forward (Recommended for Remote Access)

Since `*.cnoe.localtest.me` resolves to 127.0.0.1 (which is localhost on YOUR machine, not the cluster), the easiest approach for remote access is port-forwarding:

```bash
# Forward ArgoCD
kubectl --kubeconfig=~/remote-kubeconfig.yaml port-forward -n argocd svc/argocd-server 8080:443 &

# Forward Gitea
kubectl --kubeconfig=~/remote-kubeconfig.yaml port-forward -n gitea svc/gitea-http 8081:3000 &

# Access in browser
open https://localhost:8080  # ArgoCD
open http://localhost:8081   # Gitea
```

**Advantages**:
- Works from any remote machine
- No DNS configuration needed
- Encrypted through kubectl proxy
- Simple troubleshooting

#### Option 2: Direct Ingress Access (For Machines on Same Network as Kind Host)

If you're accessing from a machine that can resolve the kind host's IP directly (e.g., via VPN or local network), and you've configured ingress-nginx properly:

**Note**: This requires the kind cluster to use **path-based routing** or custom DNS that resolves to the kind host's IP.

For the current setup with domain-based routing (`*.cnoe.localtest.me`), port-forwarding (Option 1) is the recommended approach for remote access.

### Available Services

#### ArgoCD

```bash
# Via port-forward (recommended)
kubectl --kubeconfig=~/remote-kubeconfig.yaml port-forward -n argocd svc/argocd-server 8080:443 &
# Access: https://localhost:8080

# Get admin password
kubectl --kubeconfig=~/remote-kubeconfig.yaml -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

#### Gitea

```bash
# Via port-forward
kubectl --kubeconfig=~/remote-kubeconfig.yaml port-forward -n gitea svc/gitea-http 8081:3000 &
# Access: http://localhost:8081

# Get credentials
# Username: giteaAdmin
# Password from idpbuilder: idpbuilder get secrets -p gitea
```

#### Backstage (if deployed)

```bash
# Via port-forward
kubectl --kubeconfig=~/remote-kubeconfig.yaml port-forward -n backstage svc/backstage 7007:7007 &
# Access: http://localhost:7007
```

#### Headlamp (Kubernetes Dashboard)

```bash
# Via port-forward
kubectl --kubeconfig=~/remote-kubeconfig.yaml port-forward -n headlamp svc/headlamp 4466:4466 &
# Access: http://localhost:4466
```

### DNS Verification Script

Use the provided script to verify DNS resolution from both external and internal perspectives:

```bash
./deployment/scripts/tailscale/verify-dns-resolution.sh ~/remote-kubeconfig.yaml
```

This tests:
- External DNS: Tailscale hostname resolution
- External DNS: Ingress domain resolution
- Internal DNS: Kubernetes service DNS (from pod perspective)

### Web UI Troubleshooting

#### Cannot Access UI After Port-Forward

**Symptoms**: Port-forward starts successfully but browser shows connection refused

**Solutions**:
```bash
# Check if service is running
kubectl --kubeconfig=~/remote-kubeconfig.yaml get pods -n <namespace>

# Check service endpoints
kubectl --kubeconfig=~/remote-kubeconfig.yaml get endpoints -n <namespace>

# Verify port-forward is active
jobs  # Should show running kubectl process
```

#### 502 Bad Gateway

**Cause**: Service exists but pod is not ready

**Solutions**:
```bash
# Check pod status
kubectl --kubeconfig=~/remote-kubeconfig.yaml get pods -n <namespace>

# Check pod logs
kubectl --kubeconfig=~/remote-kubeconfig.yaml logs -n <namespace> <pod-name>
```

#### Certificate Warnings

**Cause**: Self-signed certificates used by ingress-nginx

**Solutions**:
- **Accept the risk** (temporary): Click "Advanced" → "Proceed to localhost" in browser
- **Trust the CA** (permanent): Export and trust the cluster CA certificate (see Cluster CA Distribution section)
- **Use port-forward**: Certificates are handled by kubectl, less browser warnings

### Performance Expectations

Web UI performance over Tailscale port-forward:
- **Initial page load**: <3 seconds
- **Subsequent navigation**: <1 second
- **API calls**: 50-200ms latency
- **Large asset downloads**: May see higher latency due to kubectl proxying

**Performance Tips**:
1. Keep port-forwards running persistently rather than starting/stopping
2. Use HTTP/2 if supported by the service (reduces round trips)
3. For heavy data transfers, consider direct ingress access or VPN alternatives

## Certificate Lifecycle

### Let's Encrypt Certificate Renewal

When using Tailscale HTTPS:
- **Validity**: 90 days
- **Renewal**: Automatic, handled by Tailscale operator
- **User action**: None required

### Monitoring Certificate Expiration

Check certificate expiration:

```bash
# Query Tailscale endpoint
echo | openssl s_client -connect kind-operator.tail286401.ts.net:443 2>/dev/null | openssl x509 -noout -dates

# Output shows:
# notBefore=Jan  1 00:00:00 2025 GMT
# notAfter=Mar 31 23:59:59 2025 GMT
```

Set up monitoring alerts if certificate renewal fails (check Tailscale operator logs for renewal errors).

## Security Best Practices

[Security best practices will be added during Phase 7 - Polish]

## Multi-Cluster Patterns

[Multi-cluster documentation will be added during Phase 7 - Polish]

## CI/CD Integration

### Overview

CI/CD pipelines (GitHub Actions, GitLab CI, Jenkins) require special configuration for remote cluster access since they typically don't have Tailscale installed or can't provision Let's Encrypt certificates interactively.

**Recommended Approach**: Use **cluster CA distribution** for CI/CD environments.

### GitHub Actions Example

#### Prerequisites

1. Export cluster CA certificate (from cluster host):
   ```bash
   ./deployment/scripts/tailscale/export-cluster-ca.sh cluster-ca.crt
   ```

2. Generate remote kubeconfig (same as user setup):
   ```bash
   ./deployment/scripts/tailscale/generate-kubeconfig.sh
   ```

3. Embed CA certificate in kubeconfig:
   ```bash
   # Get base64-encoded CA
   CA_DATA=$(cat cluster-ca.crt | base64 -w 0)

   # Update kubeconfig clusters section
   # Add this field to the cluster:
   #   certificate-authority-data: <CA_DATA>
   ```

4. Store as GitHub secret:
   ```bash
   # Go to: Settings → Secrets and variables → Actions
   # Create secret: KUBECONFIG_TAILSCALE
   # Paste the entire kubeconfig content
   ```

#### Workflow Example

```yaml
name: Deploy to Cluster
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Tailscale
        uses: tailscale/github-action@v2
        with:
          oauth-client-id: ${{ secrets.TAILSCALE_OAUTH_CLIENT_ID }}
          oauth-secret: ${{ secrets.TAILSCALE_OAUTH_SECRET }}
          tags: tag:ci

      - name: Setup kubectl
        uses: azure/setup-kubectl@v3
        with:
          version: 'v1.27.0'

      - name: Configure kubectl
        run: |
          mkdir -p ~/.kube
          echo "${{ secrets.KUBECONFIG_TAILSCALE }}" > ~/.kube/config
          chmod 600 ~/.kube/config

      - name: Verify connectivity
        run: |
          kubectl get nodes
          kubectl get pods -A

      - name: Deploy application
        run: |
          kubectl apply -f manifests/
          kubectl rollout status deployment/my-app -n my-namespace
```

#### Required GitHub Secrets

| Secret Name | Description | How to Obtain |
|-------------|-------------|---------------|
| `KUBECONFIG_TAILSCALE` | Full kubeconfig with embedded CA | Generated via generate-kubeconfig.sh, manually add certificate-authority-data |
| `TAILSCALE_OAUTH_CLIENT_ID` | Tailscale OAuth client ID | [Tailscale Admin Console](https://login.tailscale.com/admin/settings/oauth) → OAuth clients |
| `TAILSCALE_OAUTH_SECRET` | Tailscale OAuth client secret | Same as above |

**Tailscale OAuth Setup**:
1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/oauth)
2. Click "Generate OAuth client"
3. Set tags: `tag:ci` (create tag if needed in ACL)
4. Copy client ID and secret
5. Add ACL rule to allow `tag:ci` to access operator device:
   ```json
   "tagOwners": {
     "tag:ci": ["autogroup:admin"],
   },
   "acls": [
     {"action": "accept", "src": ["tag:ci"], "dst": ["tag:k8s-operator:*"]},
   ]
   ```

### GitLab CI Example

```yaml
deploy:
  stage: deploy
  image: bitnami/kubectl:latest
  before_script:
    # Install Tailscale
    - curl -fsSL https://tailscale.com/install.sh | sh
    - tailscale up --authkey=$TAILSCALE_AUTHKEY --hostname=gitlab-ci-$CI_PIPELINE_ID

    # Configure kubectl
    - mkdir -p ~/.kube
    - echo "$KUBECONFIG_TAILSCALE" > ~/.kube/config
    - chmod 600 ~/.kube/config

  script:
    - kubectl get nodes
    - kubectl apply -f manifests/
    - kubectl rollout status deployment/my-app -n my-namespace

  only:
    - main
```

**GitLab CI Variables** (Settings → CI/CD → Variables):
- `KUBECONFIG_TAILSCALE`: Full kubeconfig with embedded CA
- `TAILSCALE_AUTHKEY`: Pre-authentication key (reusable, expires after 90 days)

**Tailscale Auth Key Setup**:
1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys)
2. Click "Generate auth key"
3. Check "Reusable" and "Ephemeral" (cleanup after CI run)
4. Set tags: `tag:ci`
5. Copy key and add to GitLab variables

### Jenkins Pipeline Example

```groovy
pipeline {
    agent any

    environment {
        KUBECONFIG = credentials('kubeconfig-tailscale')
        TAILSCALE_AUTHKEY = credentials('tailscale-authkey')
    }

    stages {
        stage('Setup') {
            steps {
                sh '''
                    # Install Tailscale
                    curl -fsSL https://tailscale.com/install.sh | sh
                    tailscale up --authkey=$TAILSCALE_AUTHKEY --hostname=jenkins-${BUILD_ID}

                    # Verify kubectl
                    kubectl version --client
                '''
            }
        }

        stage('Verify') {
            steps {
                sh 'kubectl get nodes'
            }
        }

        stage('Deploy') {
            steps {
                sh '''
                    kubectl apply -f manifests/
                    kubectl rollout status deployment/my-app -n my-namespace
                '''
            }
        }
    }
}
```

**Jenkins Credentials**:
- `kubeconfig-tailscale`: Secret file with kubeconfig content
- `tailscale-authkey`: Secret text with Tailscale auth key

### CI/CD Security Considerations

1. **Kubeconfig Storage**:
   - Use CI platform secret management (GitHub Secrets, GitLab CI Variables, Jenkins Credentials)
   - NEVER commit kubeconfig to source control
   - Rotate credentials regularly (client certificates, auth keys)

2. **Tailscale Auth Keys**:
   - Use **ephemeral** keys for CI (automatically cleanup devices)
   - Use **reusable** keys to avoid regenerating for every run
   - Set expiration (90 days recommended)
   - Tag with `tag:ci` for ACL isolation

3. **RBAC Limitations**:
   - Create a dedicated ServiceAccount for CI with limited permissions
   - Avoid using cluster-admin certificates in CI
   - Example limited RBAC:
     ```yaml
     apiVersion: v1
     kind: ServiceAccount
     metadata:
       name: ci-deployer
       namespace: my-namespace
     ---
     apiVersion: rbac.authorization.k8s.io/v1
     kind: Role
     metadata:
       name: ci-deployer
       namespace: my-namespace
     rules:
     - apiGroups: ["apps"]
       resources: ["deployments"]
       verbs: ["get", "list", "update", "patch"]
     - apiGroups: [""]
       resources: ["pods", "pods/log"]
       verbs: ["get", "list"]
     ---
     apiVersion: rbac.authorization.k8s.io/v1
     kind: RoleBinding
     metadata:
       name: ci-deployer
       namespace: my-namespace
     subjects:
     - kind: ServiceAccount
       name: ci-deployer
       namespace: my-namespace
     roleRef:
       kind: Role
       name: ci-deployer
       apiGroup: rbac.authorization.k8s.io
     ```

4. **Network Isolation**:
   - Use Tailscale ACLs to restrict CI devices:
     ```json
     "acls": [
       {
         "action": "accept",
         "src": ["tag:ci"],
         "dst": ["tag:k8s-operator:443"]  // Only API access
       }
     ]
     ```

### Alternative: Direct API Access (Without Tailscale in CI)

For CI environments where installing Tailscale is not feasible, use a bastion/jump host:

```yaml
# GitHub Actions example with SSH jump host
- name: Deploy via Jump Host
  run: |
    # Setup SSH key
    mkdir -p ~/.ssh
    echo "${{ secrets.SSH_PRIVATE_KEY }}" > ~/.ssh/id_rsa
    chmod 600 ~/.ssh/id_rsa

    # Deploy via SSH on jump host (which has Tailscale)
    ssh -o StrictHostKeyChecking=no jump-host.example.com << 'ENDSSH'
      export KUBECONFIG=~/remote-kubeconfig.yaml
      kubectl apply -f /tmp/manifests/
      kubectl rollout status deployment/my-app
    ENDSSH
```

### Troubleshooting CI/CD Access

#### Tailscale Connection Fails in CI

**Symptoms**: `tailscale up` hangs or fails with "no network path"

**Solutions**:
```bash
# Check Tailscale service status
tailscale status

# Verify auth key is valid
# Regenerate in admin console if expired

# Check CI runner network connectivity
ping login.tailscale.com
```

#### Certificate Validation Fails

**Symptoms**: `x509: certificate signed by unknown authority`

**Solution**: Verify cluster CA is embedded in kubeconfig:
```bash
# Extract and verify certificate-authority-data
kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d | openssl x509 -text -noout
```

#### Unauthorized in CI but Works Locally

**Symptoms**: CI shows `Unauthorized` but same kubeconfig works locally

**Solution**: Check client certificate expiration:
```bash
kubectl config view --raw -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -d | openssl x509 -noout -enddate
```

If expired, regenerate kubeconfig with fresh certificates.
