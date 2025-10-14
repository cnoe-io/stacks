# Research: TLS Certificate Management for Tailscale Kubernetes API Proxy

**Date**: 2025-10-13
**Feature**: Remote Kubernetes Cluster Access via Tailscale
**Research Question**: When to use Tailscale HTTPS auto-provisioning vs. cluster CA distribution?

## Executive Summary

This research addresses TLS certificate management strategies for secure remote kubectl access via Tailscale. The cluster CA certificate is valid only for specific IPs (127.0.0.1, 10.96.0.1, 172.18.0.2), causing "certificate is valid for X, not Y" errors when connecting via Tailscale IPs. Two viable strategies exist: (1) Tailscale HTTPS auto-provisioning with Let's Encrypt certificates for the Tailscale proxy endpoint, or (2) distributing the cluster CA certificate to client trust stores. The decision depends on deployment environment, team size, and security requirements.

**Recommended Approach**: Use Tailscale HTTPS auto-provisioning for team collaboration environments (5+ users) and cluster CA distribution for local development. Production clusters should use managed certificate solutions (cloud provider load balancers with valid certificates).

## Background: Certificate Validation Problem

### Current Cluster Certificate Configuration

**Kind Cluster API Server Certificate SANs** (from `/etc/kubernetes/pki/apiserver.crt`):
- DNS: kubernetes, kubernetes.default, kubernetes.default.svc, kubernetes.default.svc.cluster.local, localdev-control-plane, localhost
- IP: 10.96.0.1 (cluster IP), 172.18.0.2 (control plane node), 127.0.0.1 (localhost)

**Problem**: When kubectl connects via Tailscale proxy (e.g., `100.x.x.x`), the API server certificate does NOT include this Tailscale IP in its SAN list, causing TLS validation errors:

```
x509: certificate is valid for 10.96.0.1, 172.18.0.2, 127.0.0.1, not 100.x.x.x
```

### Why This Happens

The kind cluster generates a self-signed CA and API server certificate during initialization, with SANs limited to the known endpoints at creation time. Tailscale IPs are dynamically assigned and not known during cluster creation, so they cannot be included in the certificate.

### Certificate Architecture with Tailscale Proxy

Two certificate validation points exist:

1. **kubectl → Tailscale Proxy TLS**: Connection from kubectl client to Tailscale proxy endpoint (e.g., `kind-operator.tail286401.ts.net:443`)
2. **Tailscale Proxy → API Server TLS**: Connection from Tailscale operator pod to Kubernetes API server (internal, uses cluster CA)

The **first connection** is where certificate validation issues occur for remote clients.

## Certificate Strategy Options

### Option 1: Tailscale HTTPS Auto-Provisioning

**How It Works**:
- Tailscale operator provisions Let's Encrypt certificates automatically for MagicDNS hostnames (e.g., `kind-operator.tail286401.ts.net`)
- Certificates are provisioned lazily on first client connection (may cause initial timeout)
- Valid for all Tailscale-connected clients without manual trust store configuration
- Requires org-level HTTPS enabled in Tailscale admin console

**Implementation Steps**:
1. Enable MagicDNS for tailnet: Tailscale Admin Console → DNS → Enable MagicDNS
2. Enable HTTPS certificates: DNS page → HTTPS Certificates → Enable
3. Configure operator with `APISERVER_PROXY=true` (already enabled in current chart)
4. Set operator hostname: `OPERATOR_HOSTNAME=kind-operator` (already configured)
5. Wait for first connection to provision certificate (10-30 seconds)
6. kubectl connects to `https://kind-operator.tail286401.ts.net:443` with valid certificate

**kubeconfig Configuration**:
```yaml
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://kind-operator.tail286401.ts.net:443
  name: kind-tailscale
contexts:
- context:
    cluster: kind-tailscale
    user: kind-admin
  name: kind-tailscale
current-context: kind-tailscale
users:
- name: kind-admin
  user:
    client-certificate-data: <base64-encoded-client-cert>
    client-key-data: <base64-encoded-client-key>
```

**Advantages**:
- ✅ No manual certificate distribution required
- ✅ Valid certificates trusted by all standard clients (browsers, kubectl, curl)
- ✅ Automatic certificate renewal (Let's Encrypt 90-day lifecycle)
- ✅ Works for multiple users without per-user configuration
- ✅ Eliminates "certificate is valid for X, not Y" errors

**Disadvantages**:
- ❌ Requires org-level Tailscale HTTPS enablement (admin access required)
- ❌ First connection timeout (certificate provisioning delay)
- ❌ Depends on external Let's Encrypt infrastructure availability
- ❌ Must use port 443 (cannot use custom ports for HTTPS auto-provisioning)

**Best For**:
- Team collaboration environments (5+ users)
- Production-like staging environments
- External contractors needing cluster access
- Users without system administrator privileges (cannot modify trust store)

---

### Option 2: Cluster CA Certificate Distribution

**How It Works**:
- Export cluster CA certificate from Kubernetes control plane
- Distribute CA certificate to each user's trust store (OS-level or kubectl-level)
- kubectl validates API server certificate using trusted CA
- TLS validation succeeds for any IP/hostname since CA issued the certificate

**Implementation Steps**:

1. **Export Cluster CA Certificate**:
```bash
# Extract CA certificate from kind cluster
docker exec localdev-control-plane cat /etc/kubernetes/pki/ca.crt > /tmp/kind-ca.crt

# Or extract from kubeconfig
kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > /tmp/kind-ca.crt
```

2. **Distribute to Users**:
```bash
# Option A: Add to OS trust store (macOS)
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /tmp/kind-ca.crt

# Option B: Add to OS trust store (Linux)
sudo cp /tmp/kind-ca.crt /usr/local/share/ca-certificates/kind-cluster-ca.crt
sudo update-ca-certificates

# Option C: kubectl-level trust (no OS changes required)
kubectl config set-cluster kind-tailscale \
  --server=https://100.x.x.x:443 \
  --certificate-authority=/path/to/kind-ca.crt
```

3. **Configure kubeconfig**:
```yaml
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority: /Users/username/.kube/kind-ca.crt
    server: https://100.x.x.x:443
  name: kind-tailscale
contexts:
- context:
    cluster: kind-tailscale
    user: kind-admin
  name: kind-tailscale
current-context: kind-tailscale
users:
- name: kind-admin
  user:
    client-certificate-data: <base64-encoded-client-cert>
    client-key-data: <base64-encoded-client-key>
```

**Advantages**:
- ✅ No Tailscale HTTPS requirement (works with free Tailscale plans)
- ✅ No external dependencies (Let's Encrypt, Tailscale HTTPS infrastructure)
- ✅ Immediate connection (no certificate provisioning delay)
- ✅ Works with custom ports if needed
- ✅ Validates against cluster's actual CA (tighter security)

**Disadvantages**:
- ❌ Manual distribution required for each user
- ❌ Trust store modification requires system administrator privileges (macOS/Linux)
- ❌ Certificate file management (users must keep file accessible)
- ❌ CA rotation requires redistribution to all users
- ❌ kubectl-level trust (`certificate-authority` path) breaks if file moved/deleted
- ❌ Different procedures for macOS/Linux/Windows

**Best For**:
- Local development (single user)
- Small teams (2-4 users)
- Environments without Tailscale HTTPS capability
- Kubernetes administrators who can modify system trust stores
- Scenarios requiring custom ports

---

### Option 3: `--insecure-skip-tls-verify` Flag (TESTING ONLY)

**How It Works**:
- kubectl skips TLS certificate validation entirely
- Useful for rapid testing and troubleshooting certificate issues
- Can be set per-command or in kubeconfig

**Implementation**:
```bash
# Per-command usage
kubectl get nodes --insecure-skip-tls-verify

# Or in kubeconfig
kubectl config set-cluster kind-tailscale \
  --server=https://100.x.x.x:443 \
  --insecure-skip-tls-verify=true
```

**Security Implications**:
- ⚠️ **Man-in-the-middle attacks**: Attacker can intercept and modify traffic
- ⚠️ **Certificate spoofing**: Fake certificates are accepted as valid
- ⚠️ **Identity spoofing**: Attacker can impersonate API server
- ⚠️ **Data exposure**: Unencrypted traffic vulnerable to eavesdropping

**When to Use**:
- ✅ Local development testing to verify connectivity
- ✅ Troubleshooting certificate configuration issues
- ✅ Temporary access when proper certificates are being provisioned
- ✅ Non-production environments with no sensitive data

**Never Use In**:
- ❌ Production clusters
- ❌ Staging environments with production data
- ❌ Multi-tenant clusters
- ❌ Environments handling PII or sensitive data
- ❌ Clusters accessible from untrusted networks

**Best Practices**:
- Use only for initial connectivity verification
- Replace with proper certificate solution immediately
- Document usage in runbooks as temporary workaround
- Implement additional security controls (firewalls, network policies) if used longer than 24 hours
- Monitor for unauthorized usage (audit logs for insecure connections)

---

## Decision Matrix

| Scenario | Certificate Strategy | Rationale | Implementation Effort | Security Posture |
|----------|---------------------|-----------|----------------------|------------------|
| **Local dev (kind cluster, single user)** | Cluster CA distribution | No Tailscale HTTPS required; user likely has admin access to trust store; immediate connectivity without provisioning delay | LOW - Single user, export CA once, add to local trust store | HIGH - Validates against cluster CA, no external dependencies |
| **Team collaboration (5+ users)** | Tailscale HTTPS auto-provisioning | No per-user trust store configuration; automatic renewal; works across all OS types; professional appearance with valid certificates | MEDIUM - Requires org-level Tailscale HTTPS enablement, initial setup delay | HIGH - Let's Encrypt certificates, automatic renewal, no trust store modifications |
| **Small team (2-4 users)** | Cluster CA distribution | Feasible to distribute CA manually; users may prefer control over trust store; no Tailscale HTTPS requirement | MEDIUM - Distribute CA to each user, document OS-specific procedures | HIGH - Validates against cluster CA, predictable trust model |
| **Production cluster** | Cloud provider load balancer + valid certificates | Use managed certificate solutions (AWS ACM, Azure Key Vault, Let's Encrypt via cert-manager); Tailscale should not be primary access method | HIGH - Requires cert-manager, external-dns, cloud provider integration | VERY HIGH - Publicly trusted certificates, HA load balancers, certificate rotation automation |
| **Testing/troubleshooting (temporary)** | `--insecure-skip-tls-verify` | Rapid connectivity verification; isolate certificate issues from connectivity issues; acceptable for non-production | ZERO - Single flag in kubectl command | LOW - No TLS validation, temporary only |
| **Staging environment (production-like)** | Tailscale HTTPS auto-provisioning | Matches production certificate handling patterns; supports multiple users; demonstrates production-ready configuration | MEDIUM - Tailscale HTTPS enablement, operator configuration | HIGH - Let's Encrypt certificates, matches production certificate lifecycle |
| **External contractors (temporary access)** | Tailscale HTTPS auto-provisioning | No trust store modification required on contractor machines; time-limited access via Tailscale ACLs; no certificate distribution logistics | LOW - Contractors join Tailscale network, receive kubeconfig with HTTPS endpoint | MEDIUM-HIGH - Valid certificates, access controlled via Tailscale ACLs, no persistent trust store changes |
| **CI/CD pipelines** | Cluster CA distribution | Predictable certificate path in container images; no external dependencies (Let's Encrypt); works in air-gapped environments | MEDIUM - Add CA to container image or mount as secret; configure in pipeline kubeconfig | HIGH - Validates against cluster CA, no runtime provisioning delay, air-gap compatible |
| **Windows users** | Tailscale HTTPS auto-provisioning | Avoids Windows trust store complexity (certmgr.msc); consistent cross-platform experience; no administrator privileges required | LOW - Same configuration as macOS/Linux users | HIGH - Let's Encrypt certificates, no OS-specific trust store procedures |

## Recommended Implementation

### Phase 1: Enable Tailscale HTTPS Auto-Provisioning (Primary)

**Target Users**: All remote users, default configuration

1. **Prerequisites Check**:
   - Verify Tailscale HTTPS enabled: Admin Console → DNS → HTTPS Certificates (must show "Enabled")
   - Confirm operator hostname: `kind-operator` (already set in TailscaleOperatorChart)
   - Validate `APISERVER_PROXY=true` in operator deployment (already configured)

2. **Update Documentation** (`docs/tailscale-cluster-access.md`):
   - Primary kubectl configuration uses `https://kind-operator.tail286401.ts.net:443`
   - Note initial connection delay (certificate provisioning)
   - Include troubleshooting steps for provisioning timeout

3. **Test Connection**:
   ```bash
   # First connection (may take 30 seconds)
   kubectl get nodes --request-timeout=60s

   # Subsequent connections (normal speed)
   kubectl get nodes
   ```

4. **Distribute kubeconfig**:
   - Generate helper script: `deployment/scripts/tailscale/generate-kubeconfig.sh`
   - Extracts client certificates from cluster
   - Writes kubeconfig with Tailscale HTTPS endpoint
   - No CA certificate needed (Let's Encrypt trusted by default)

### Phase 2: Document Cluster CA Distribution (Fallback)

**Target Users**: Users without Tailscale HTTPS, CI/CD pipelines, air-gapped environments

1. **Create Export Script** (`deployment/scripts/tailscale/export-cluster-ca.sh`):
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail

   # Extract CA certificate from kind cluster
   docker exec localdev-control-plane cat /etc/kubernetes/pki/ca.crt > kind-ca.crt

   echo "Cluster CA certificate exported to: kind-ca.crt"
   echo ""
   echo "Installation instructions:"
   echo "  macOS:  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain kind-ca.crt"
   echo "  Linux:  sudo cp kind-ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates"
   echo "  kubectl: kubectl config set-cluster kind-tailscale --certificate-authority=\$(pwd)/kind-ca.crt"
   ```

2. **Document Trust Store Procedures** (`docs/tailscale-cluster-access.md`):
   - OS-specific installation commands (macOS, Linux, Windows)
   - kubectl-only configuration (no OS changes)
   - Verification steps: `openssl verify -CAfile kind-ca.crt <(kubectl config view --raw --minify --flatten -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -d)`

3. **CI/CD Integration Example** (GitHub Actions):
   ```yaml
   - name: Configure kubectl with cluster CA
     run: |
       echo "${{ secrets.KIND_CLUSTER_CA }}" | base64 -d > /tmp/kind-ca.crt
       kubectl config set-cluster kind-tailscale \
         --server=https://${{ secrets.TAILSCALE_OPERATOR_IP }}:443 \
         --certificate-authority=/tmp/kind-ca.crt
   ```

### Phase 3: Testing and Troubleshooting

**Document `--insecure-skip-tls-verify` Usage**:

Include in troubleshooting section with clear warnings:

```markdown
## Troubleshooting: Certificate Validation Errors

### Quick Test (Temporary Only)

To verify connectivity independent of certificate issues:

```bash
kubectl get nodes --insecure-skip-tls-verify
```

⚠️ **WARNING**: This flag disables TLS validation entirely. Use ONLY for:
- Initial connectivity testing (10 minutes maximum)
- Troubleshooting certificate configuration
- Non-production environments

**DO NOT** use in production or with sensitive data. An attacker can intercept and modify your traffic.

### Proper Solutions

After verifying connectivity works with `--insecure-skip-tls-verify`, implement proper certificate handling:
1. Enable Tailscale HTTPS (recommended for teams)
2. Distribute cluster CA certificate (recommended for individual users)
```

## Technical Details: Tailscale HTTPS Certificate Provisioning

### How Certificates Are Provisioned

From Tailscale documentation analysis:

1. **Lazy Provisioning**: Certificates are provisioned lazily on first client connection, not during operator startup
2. **Provisioning Time**: 10-30 seconds for Let's Encrypt DNS challenge completion
3. **First Request Impact**: First kubectl command may timeout or take 30+ seconds
4. **Subsequent Requests**: Normal performance after initial provisioning
5. **Certificate Lifecycle**: 90-day validity, automatic renewal before expiration

### Operator Configuration for HTTPS

Current `TailscaleOperatorChart` configuration (verified correct):

```typescript
env: [
  {
    name: 'APISERVER_PROXY',
    value: 'true', // Enables in-process API server proxy
  },
  {
    name: 'OPERATOR_HOSTNAME',
    value: `${props.clusterName}-operator`, // e.g., kind-operator
  },
  // OAuth credentials omitted for brevity
]
```

**Key Points**:
- `APISERVER_PROXY=true`: Enables in-process TLS server that proxies to Kubernetes API
- Operator gets LetsEncrypt certificate for MagicDNS name (e.g., `kind-operator.tail286401.ts.net`)
- Certificate provisioned on first API call (client may see timeout)
- Port 443 is automatically exposed by Tailscale (do not create additional Kubernetes Service)

### ProxyGroup vs In-Process Proxy

**Current Implementation**: In-process proxy mode (`APISERVER_PROXY=true` in operator deployment)

**ProxyGroup Conflict**: The current `TailscaleOperatorChart` creates a `ProxyGroup` resource when `enableHA` is true or environment is staging/production. This creates a **conflict** with in-process proxy mode:

- **In-process proxy**: Operator pod itself acts as TLS proxy, provisions certificates
- **ProxyGroup**: Operator creates separate proxy pods (StatefulSet) with their own certificate handling

**Decision**: Remove `ProxyGroup` resource for dev environments to eliminate conflicts. For staging/production, evaluate if HA ProxyGroup provides meaningful benefits over operator pod restart.

**Recommended Chart Update**:
```typescript
// Remove or conditionally disable ProxyGroup creation
// Current implementation at lines 329-348 should be removed for dev environments
if (props.enableHA && props.environmentName === 'production') {
  // Only create ProxyGroup for production HA requirements
  new ProxyGroup(this, 'api-server-proxy', {
    // ... existing configuration
  });
}
```

## API Server Certificate Architecture

### Certificate Chain

```
Remote kubectl
    ↓
    TLS (Let's Encrypt cert for kind-operator.tail286401.ts.net)
    ↓
Tailscale Operator Pod (in-process proxy)
    ↓
    TLS (cluster CA cert for 10.96.0.1, 172.18.0.2, 127.0.0.1)
    ↓
Kubernetes API Server (kind control plane)
```

### Why Two Certificate Layers?

1. **External Layer** (kubectl → operator):
   - Must validate for Tailscale IP/hostname (e.g., `kind-operator.tail286401.ts.net`)
   - Options: Let's Encrypt (Tailscale HTTPS) or distributed cluster CA

2. **Internal Layer** (operator → API server):
   - Always uses cluster CA certificate
   - Operator has cluster CA in its ServiceAccount (automatic Kubernetes credential mounting)
   - No user configuration required

### Impersonation and Authentication

Tailscale operator uses **impersonation** for authentication:

1. User connects via Tailscale with identity (e.g., `vpittamp@github`)
2. Operator validates Tailscale identity via Tailscale control plane
3. Operator impersonates Kubernetes user based on identity mapping:
   - Tailscale user → Kubernetes user/groups (configured in operator chart)
   - Example: `vpittamp@github` → `system:masters` group (cluster-admin)
4. Operator makes API request to Kubernetes API server with impersonated identity
5. Kubernetes RBAC evaluates request based on impersonated user/groups

**RBAC Configuration** (already in `TailscaleOperatorChart`):
```typescript
rules: [
  {
    apiGroups: [''],
    resources: ['users', 'groups'],
    verbs: ['impersonate'],
  },
  // Additional impersonation resources for AWS EKS, etc.
]
```

## Comparison with Alternative Approaches

### SSH Port Forwarding

**Pattern**: SSH into cluster host, forward port 6443 (API server)

```bash
ssh -L 6443:localhost:6443 root@cluster-host
kubectl --kubeconfig=local-kubeconfig get nodes
```

**Advantages**:
- ✅ No certificate issues (localhost always trusted)
- ✅ No additional Kubernetes resources (operator, proxy)
- ✅ Works with any SSH-accessible host

**Disadvantages**:
- ❌ Requires SSH access to cluster host (not available in managed Kubernetes)
- ❌ Requires persistent SSH session (breaks if connection drops)
- ❌ Port conflict if multiple clusters forwarded to same port
- ❌ No identity-based access control (host-level SSH permissions only)

### Tailscale Serve

**Pattern**: Use `tailscale serve` to expose API server port directly

```bash
# On cluster host (not in Kubernetes)
tailscale serve https+insecure://localhost:6443 /
```

**Advantages**:
- ✅ Simple configuration (single command)
- ✅ No Kubernetes operator required

**Disadvantages**:
- ❌ Exposes raw API server without identity-based auth
- ❌ Requires Tailscale CLI on cluster host (not in Kubernetes cluster)
- ❌ `https+insecure` still requires certificate handling on kubectl side
- ❌ No impersonation (all users share same ServiceAccount)

### VPN (Traditional)

**Pattern**: Connect to VPN, access API server via internal IP

**Advantages**:
- ✅ Familiar model for enterprise environments
- ✅ Centralized access control

**Disadvantages**:
- ❌ Complex VPN infrastructure (certificates, gateways, routing)
- ❌ Split-tunnel configuration issues
- ❌ Performance overhead (all traffic tunneled)
- ❌ User experience friction (VPN client, connection stability)

**Why Tailscale is Better**: Mesh network model eliminates VPN gateway bottleneck, zero-config peer-to-peer connections, faster performance, better reliability.

## Implementation Checklist

### Pre-Deployment Validation

- [ ] Verify Tailscale HTTPS enabled: Admin Console → DNS → HTTPS Certificates
- [ ] Confirm operator hostname: `OPERATOR_HOSTNAME=kind-operator` in chart
- [ ] Validate `APISERVER_PROXY=true` in operator deployment
- [ ] Remove or disable ProxyGroup for dev environment (eliminate conflicts)
- [ ] Test first connection timeout expectation (30-60 seconds)

### Documentation Updates

- [ ] Create `docs/tailscale-cluster-access.md` with setup guide
- [ ] Document Tailscale HTTPS as primary method
- [ ] Document cluster CA distribution as fallback
- [ ] Include troubleshooting section with `--insecure-skip-tls-verify` warnings
- [ ] Add certificate architecture diagrams
- [ ] Create quickstart script: `deployment/scripts/tailscale/generate-kubeconfig.sh`

### Testing Plan

- [ ] Test kubectl from Mac via Tailscale (tmux pane %30)
- [ ] Verify first connection delay (certificate provisioning)
- [ ] Test subsequent connections (normal performance)
- [ ] Validate port-forward: `kubectl port-forward -n argocd svc/argocd-server 8080:443`
- [ ] Test web UI access: `https://argocd.cnoe.localtest.me:8443` (requires ingress updates)
- [ ] Test cluster CA distribution workflow (export, trust store addition, kubectl configuration)
- [ ] Verify impersonation: `kubectl auth whoami` shows Tailscale identity
- [ ] Test certificate renewal (wait 90 days or force renewal)

### Common Errors and Resolutions

| Error Message | Cause | Resolution |
|---------------|-------|------------|
| `x509: certificate is valid for 10.96.0.1, not 100.x.x.x` | Connecting to Tailscale IP with cluster CA validation | Enable Tailscale HTTPS or distribute cluster CA |
| `TLS handshake timeout` | First connection while certificate provisioning | Wait 30 seconds, retry with `--request-timeout=60s` |
| `unable to connect to server: EOF` | Tailscale operator not running or APISERVER_PROXY=false | Check operator pod: `kubectl get pods -n tailscale`, verify APISERVER_PROXY env var |
| `certificate signed by unknown authority` | Cluster CA not in trust store (when using CA distribution method) | Add CA to trust store (see `export-cluster-ca.sh` instructions) |
| `Unauthorized` | Impersonation not configured or Tailscale identity not mapped to Kubernetes groups | Verify impersonationGrants in TailscaleOperatorChart, check Tailscale ACLs |
| `ProxyGroup not ready` | ProxyGroup conflicts with in-process proxy | Remove ProxyGroup resource for dev environments |

## Alternatives Considered

### 1. Custom Certificate Generation with Tailscale IPs

**Approach**: Regenerate API server certificate with Tailscale IPs in SAN

**Why Rejected**:
- Requires modifying control plane certificates (risky in production)
- Tailscale IPs can change (DHCP lease expiration)
- kind clusters regenerate certificates on restart
- Does not scale to multiple clusters (each needs unique certificate)

### 2. cert-manager with Let's Encrypt

**Approach**: Use cert-manager to provision Let's Encrypt certificates for API server

**Why Rejected**:
- Requires DNS challenge (public DNS records)
- kind cluster does not have stable public IP
- Adds complexity (cert-manager installation, DNS configuration)
- Tailscale HTTPS provides same benefit with zero additional infrastructure

### 3. Mutual TLS (mTLS) with Client Certificates

**Approach**: Generate client certificates for each user, bypass API server certificate validation

**Why Rejected**:
- Does not solve server certificate validation (still requires cluster CA or --insecure-skip-tls-verify)
- Adds client certificate distribution burden
- Kubernetes already uses client certificates (this is default authentication)
- Does not address TLS validation problem

### 4. Nginx/Traefik Reverse Proxy with Custom Certificates

**Approach**: Deploy reverse proxy with custom certificates, proxy to API server

**Why Rejected**:
- Adds additional infrastructure (nginx/traefik deployment)
- Certificate management still required (back to square one)
- Tailscale operator provides same functionality with better integration
- Increases attack surface (additional network hop)

## Conclusion

**Primary Recommendation**: Use Tailscale HTTPS auto-provisioning for team collaboration environments. This eliminates manual certificate distribution, provides automatic renewal, and works consistently across all operating systems.

**Fallback Recommendation**: Document cluster CA distribution workflow for users without Tailscale HTTPS capability, CI/CD pipelines, and air-gapped environments.

**Testing Recommendation**: `--insecure-skip-tls-verify` is acceptable ONLY for initial connectivity verification in non-production environments. Document this as temporary workaround with clear security warnings.

**Implementation Priority**:
1. Enable Tailscale HTTPS (org-level admin task)
2. Update documentation with HTTPS endpoint as primary configuration
3. Create helper scripts for kubeconfig generation and CA export
4. Test end-to-end connectivity from Mac via Tailscale
5. Document troubleshooting procedures and common errors

---

## References

- [Tailscale HTTPS Certificate Provisioning](https://tailscale.com/kb/1153/enabling-https)
- [Tailscale Kubernetes Operator API Server Proxy](https://tailscale.com/kb/1437/kubernetes-operator-api-server-proxy)
- [Kubernetes PKI Certificates and Requirements](https://kubernetes.io/docs/setup/best-practices/certificates/)
- [kubectl Security Best Practices](https://kubernetes.io/docs/reference/kubectl/kubectl/)
- [Let's Encrypt Certificate Lifecycle](https://letsencrypt.org/docs/certificate-compatibility/)
