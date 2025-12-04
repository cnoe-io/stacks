# Research: Tailscale Services Migration

**Feature**: 101-improve-tailscale
**Date**: 2025-12-04
**Status**: Complete

## Executive Summary

Tailscale Services (beta) provides stable service endpoints that survive cluster recreation. This research confirms the feature meets our requirements and documents the exact implementation approach.

## Research Areas

### 1. Tailscale Services Feature Availability

**Decision**: Use Tailscale Services with `--service` flag

**Rationale**:
- Tailscale Services is available in v1.86.0+, and cluster runs v1.90.9 (confirmed)
- Services provide stable virtual IPs that don't change on device recreation
- Native support for the use case of exposing Kubernetes services remotely

**Alternatives Considered**:
- **Persistent Tailscale state (PVC)**: More complex, requires StatefulSet, state tied to cluster
- **Auto-delete old devices**: Current approach, requires grace period (120s), error-prone
- **Accept suffixed hostnames**: Poor UX, URLs change on recreation

**Sources**:
- [Tailscale Services Documentation](https://tailscale.com/kb/1552/tailscale-services)
- [Tailscale Services Blog](https://tailscale.com/blog/services-beta)

---

### 2. `--service` Flag Syntax

**Decision**: Use CLI `--service=svc:<name>` flag with `tailscale serve`

**Syntax Confirmed**:
```bash
# For HTTPS service (ArgoCD)
tailscale serve --service=svc:argocd --https=443 https+insecure://127.0.0.1:8443

# For HTTP service (Langfuse)
tailscale serve --service=svc:langfuse --https=443 http://127.0.0.1:3000
```

**Key Details**:
- When using `--service`, background mode is automatic (no `-bg` needed)
- The `--https=443` flag exposes on HTTPS port 443 with automatic TLS cert
- Local target can be `http://`, `https://`, or `https+insecure://` for self-signed

**Alternative (Configuration File)**:
```json
{
  "version": "0.0.1",
  "services": {
    "svc:argocd": {
      "endpoints": {
        "tcp:443": "https://localhost:8443"
      }
    }
  }
}
```
Not recommended for our use case - CLI is simpler for single-endpoint services.

**Sources**:
- [Tailscale Serve Command](https://tailscale.com/kb/1242/tailscale-serve)
- [Services Configuration File](https://tailscale.com/kb/1589/tailscale-services-configuration-file)

---

### 3. Tag-Based Auth Key Requirements

**Decision**: Create new auth key with `tag:k8s-services` tag

**Requirements Confirmed**:
- **Mandatory**: Service host devices MUST use tag-based identity
- User-authenticated devices CANNOT be service hosts
- Auth key must be: reusable, ephemeral, tagged

**Implementation**:
1. Generate new auth key in Tailscale Admin Console:
   - Settings → Keys → Generate auth key
   - Enable: Reusable, Ephemeral
   - Add tag: `tag:k8s-services`

2. Update Azure Key Vault secret `tailscale-auth-key` with new key

**Sources**:
- [Tailscale Services Documentation](https://tailscale.com/kb/1552/tailscale-services) - "Any device you want to use as a Service host must use a tag-based identity"

---

### 4. ACL Auto-Approvers Configuration

**Decision**: Extend existing ACL with `tag:k8s-services` tag and service auto-approvers

**Current ACL Structure** (relevant portions):
```json
{
  "tagOwners": {
    "tag:k8s-operator": ["vpittamp@github"],
    "tag:k8s": ["tag:k8s-operator", "vpittamp@github"]
  },
  "autoApprovers": {
    "routes": {
      "10.244.0.0/16": ["tag:k8s", "vpittamp@github"],
      "10.96.0.0/16": ["tag:k8s", "vpittamp@github"]
    }
  }
}
```

**Updated ACL Configuration** (additions in comments):
```json
{
  "tagOwners": {
    "tag:k8s-operator": ["vpittamp@github"],
    "tag:k8s": ["tag:k8s-operator", "vpittamp@github"],
    // NEW: Add k8s-services tag for service host devices
    "tag:k8s-services": ["vpittamp@github"]
  },
  "autoApprovers": {
    "routes": {
      "10.244.0.0/16": ["tag:k8s", "vpittamp@github"],
      "10.96.0.0/16": ["tag:k8s", "vpittamp@github"]
    },
    // NEW: Add service auto-approvers
    "services": {
      "svc:argocd": ["tag:k8s-services"],
      "svc:langfuse": ["tag:k8s-services"],
      "svc:k8s-api": ["tag:k8s-services"]
    }
  },
  "acls": [
    // ... existing rules ...
    // NEW: Allow access to k8s-services tagged devices
    {
      "action": "accept",
      "src": ["vpittamp@github"],
      "dst": ["tag:k8s-services:*"]
    },
    {
      "action": "accept",
      "src": ["tag:k8s-services"],
      "dst": ["tag:k8s:*", "tag:k8s-operator:*"]
    }
  ]
}
```

**Key Changes**:
1. Add `tag:k8s-services` to `tagOwners` (owned by `vpittamp@github`)
2. Add `services` block to `autoApprovers` with explicit service names
3. Add ACL rules to allow traffic to/from `tag:k8s-services` devices

**Alternative**: Reuse existing `tag:k8s` for services instead of new tag. However, separate tag provides cleaner separation of concerns (subnet routers vs service hosts).

**Sources**:
- [Tailscale Services Documentation](https://tailscale.com/kb/1552/tailscale-services)

---

### 5. Beta Limitations

**Decision**: Accept beta limitations - they don't impact our use case

**Confirmed Limitations**:
| Limitation | Impact on Our Use Case |
|------------|----------------------|
| TCP-only transport | **No impact** - Our services use HTTPS over TCP:443 |
| No hairpinning (host can't access its own service) | **No impact** - Pods don't need self-access |
| No outgoing connections from service VIP | **No impact** - VIP only receives traffic |
| Layer 3 (UDP) endpoints Linux-only | **No impact** - We use Layer 7 (HTTPS) |

**Risk Assessment**: Low - all limitations are acceptable for our production use.

**Sources**:
- [Tailscale Services Documentation](https://tailscale.com/kb/1552/tailscale-services)

---

### 6. Service Registration Process

**Decision**: Services auto-register on pod startup via `tailscale serve --service`

**Process**:
1. Pod starts, runs `tailscale up` with tagged auth key
2. Device registered to tailnet with `tag:k8s-services`
3. Pod runs `tailscale serve --service=svc:argocd --https=443 ...`
4. Tailscale control plane sees service advertisement
5. ACL auto-approver approves registration (matches `tag:k8s-services`)
6. Service becomes available at stable URL

**Recovery on Cluster Recreation**:
1. Old cluster deleted → old devices become offline
2. Tailscale eventually removes offline devices (no cleanup needed)
3. New cluster starts → new pods register to SAME service names
4. Services immediately available at same URLs

**Sources**:
- [Tailscale Services Documentation](https://tailscale.com/kb/1552/tailscale-services)

---

### 7. Service URL Format

**Decision**: Use `svc:<name>.<tailnet>.ts.net` format

**URL Examples**:
- ArgoCD: `https://svc:argocd.tail286401.ts.net`
- Langfuse: `https://svc:langfuse.tail286401.ts.net`
- K8s API: `https://svc:k8s-api.tail286401.ts.net`

**Note**: The exact URL format may vary by tailnet configuration. Test after initial deployment.

---

### 8. Existing Chart Analysis

**Current Implementation** (to be updated):

**ArgoCD Chart** (`argocd-tailscale-serve-chart.ts`):
```bash
# Current:
tailscale serve --bg https+insecure://127.0.0.1:${PORT_FWD}

# Updated:
tailscale serve --service=svc:argocd --https=443 https+insecure://127.0.0.1:${PORT_FWD}
```

**Langfuse Chart** (`langfuse-tailscale-serve-chart.ts`):
```bash
# Current:
tailscale serve --bg http://127.0.0.1:${PORT_FWD}

# Updated:
tailscale serve --service=svc:langfuse --https=443 http://127.0.0.1:${PORT_FWD}
```

**Key Changes**:
- Remove `--bg` flag (automatic with `--service`)
- Add `--service=svc:<name>` flag
- Add `--https=443` to specify exposed port
- Remove `TS_HOSTNAME` env var (no longer needed for device hostname)

---

## Implementation Checklist

### Tailscale Admin Console (One-Time Setup)

- [ ] Create tag `tag:k8s-services` in ACL tagOwners
- [ ] Define service `svc:argocd` with endpoint `tcp:443`
- [ ] Define service `svc:langfuse` with endpoint `tcp:443`
- [ ] Define service `svc:k8s-api` with endpoint `tcp:443` (optional)
- [ ] Add auto-approvers for services
- [ ] Generate new tagged auth key (reusable, ephemeral, `tag:k8s-services`)

### Azure Key Vault

- [ ] Update `tailscale-auth-key` secret with new tagged auth key

### CDK8s Charts

- [ ] Update `ArgoCdTailscaleServeChart` with `--service` flag
- [ ] Update `LangfuseTailscaleServeChart` with `--service` flag
- [ ] Add chart props for service name configuration
- [ ] Update documentation

### Testing

- [ ] Deploy updated charts
- [ ] Verify service URLs resolve
- [ ] Test cluster recreation (hostname stability)
- [ ] Verify authentication works
