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

[Port forwarding documentation will be added during Phase 4 implementation]

## Web UI Access

[Web UI access documentation will be added during Phase 5 implementation]

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

[CI/CD integration patterns will be added during Phase 6 - Cluster CA Distribution]
