# CoreDNS Configuration Requirements for Tailscale Endpoints

**Research Question**: What CoreDNS rewrite rules are needed for resolving Tailscale hostnames from inside the cluster?

**Context**:
- idpBuilder creates CoreDNS rewrite rules for ingress-nginx (e.g., `*.cnoe.localtest.me` → `ingress-nginx-controller.svc`)
- FR-007 requirement: "Resolve cluster service hostnames correctly both inside and outside cluster"
- Tailscale provides MagicDNS for `*.ts.net` external resolution
- In-cluster pods need to resolve Tailscale operator hostname (e.g., `kind-operator-7.tail286401.ts.net`)

**Research Date**: 2025-10-13

---

## CoreDNS Requirements

**Answer**: **No CoreDNS rewrite rules required** for basic API server proxy access. Tailscale MagicDNS handles external resolution, and internal cluster services don't need to resolve Tailscale hostnames by default.

### Current CoreDNS Configuration

The idpBuilder-created cluster has the following CoreDNS setup:

```yaml
# /etc/coredns/Corefile (from kube-system/coredns ConfigMap)
.:53 {
    errors
    health {
       lameduck 5s
    }
    ready

    import ../coredns-configs/*.conf  # Import custom configs

    kubernetes cluster.local in-addr.arpa ip6.arpa {
       pods insecure
       fallthrough in-addr.arpa ip6.arpa
       ttl 30
    }
    prometheus :9153
    forward . /etc/resolv.conf {
       max_concurrent 1000
    }
    cache 30
    loop
    reload
    loadbalance
}
```

**Key Observations**:
1. `import ../coredns-configs/*.conf` - Loads custom configurations from ConfigMaps
2. `coredns-conf-custom` ConfigMap exists but contains placeholder text: `# insert custom rules here`
3. `coredns-conf-default` ConfigMap exists (idpBuilder-managed rewrite rules for ingress-nginx)
4. Default forwarding to `/etc/resolv.conf` handles upstream DNS (including Tailscale MagicDNS)

### Tailscale MagicDNS Integration

From Tailscale operator logs:
```
{"logger":"dns-records-reconciler","msg":"DNSConfig does not exist, not creating DNS records"}
```

This indicates:
- **No DNSConfig CRD is currently deployed** in the cluster
- Tailscale operator supports optional `DNSConfig` resource for in-cluster MagicDNS resolution
- Without DNSConfig, pods rely on upstream DNS forwarding for `*.ts.net` names

---

## DNS Resolution Flow

### 1. External (kubectl from Mac)

**Scenario**: Remote user runs `kubectl get nodes` from Mac connected to Tailscale network

```
kubectl command
  ↓
kubectl config: server: https://kind-operator-7.tail286401.ts.net:443
  ↓
macOS DNS resolver
  ↓
Tailscale MagicDNS (100.100.100.100)
  ↓
Resolves: kind-operator-7.tail286401.ts.net → 100.x.x.x (Tailscale IP)
  ↓
TCP connection to 100.x.x.x:443 (operator pod)
  ↓
In-process API proxy in tailscale-operator pod
  ↓
Forwarded to: https://kubernetes.default.svc:443 (cluster API server)
```

**DNS Query**: Handled by **Tailscale MagicDNS** on client machine (Mac)
**No CoreDNS involvement**: Query happens on client side before reaching cluster

### 2. Internal (pod-to-pod via Tailscale hostname) - OPTIONAL USE CASE

**Scenario**: Pod inside cluster needs to call another pod via Tailscale MagicDNS name (e.g., service mesh, egress proxy)

**WITHOUT DNSConfig** (current state):
```
Pod DNS query: kind-operator-7.tail286401.ts.net
  ↓
CoreDNS (pod's nameserver from /etc/resolv.conf)
  ↓
No match in cluster.local domain
  ↓
Forward to upstream: /etc/resolv.conf (node DNS)
  ↓
Node DNS (systemd-resolved or /etc/resolv.conf)
  ↓
If node is NOT on Tailscale network: **RESOLUTION FAILS**
  ↓
If node IS on Tailscale network: Resolves to 100.x.x.x
```

**WITH DNSConfig** (optional enhancement):
```
Pod DNS query: kind-operator-7.tail286401.ts.net
  ↓
CoreDNS (pod's nameserver)
  ↓
Stub zone forward: ts.net → Tailscale nameserver (10.96.x.x)
  ↓
Tailscale k8s-nameserver (deployed by DNSConfig)
  ↓
Queries Tailscale API for MagicDNS records
  ↓
Returns: 100.x.x.x (Tailscale IP)
```

---

## Implementation Decision

### Option 1: No CoreDNS Changes (RECOMMENDED)

**Use Case**: kubectl access from external Tailscale-connected devices only

**Configuration**: Use default CoreDNS with upstream forwarding

**Pros**:
- Zero configuration required
- MagicDNS resolution happens on client side (Mac, laptop)
- Cluster nodes don't need Tailscale connectivity
- Operator pod handles API proxy internally (no DNS involved)

**Cons**:
- Pods inside cluster cannot resolve `*.ts.net` names unless cluster nodes have Tailscale
- Not suitable if pods need to call Tailscale services by MagicDNS name

**When to use**:
- Remote kubectl access (primary use case for FR-001 to FR-005)
- Web UI access via Tailscale-connected browsers
- Port-forward scenarios (client resolves hostname, kubectl proxies traffic)

### Option 2: Add Tailscale DNSConfig + CoreDNS Stub Zone (ADVANCED)

**Use Case**: Pods inside cluster need to resolve Tailscale MagicDNS names for egress proxies or service mesh

**Configuration**:
1. Deploy `DNSConfig` CRD to enable Tailscale k8s-nameserver
2. Add CoreDNS stub zone forwarding to `coredns-conf-custom`:

```conf
# /etc/coredns-configs/custom.conf (via kube-system/coredns-conf-custom ConfigMap)
ts.net:53 {
    errors
    cache 30
    forward . <NAMESERVER_IP>  # Get from DNSConfig.status.nameserver.ip
}
```

3. Restart CoreDNS pods to reload configuration

**Pros**:
- Enables in-cluster workloads to resolve `*.ts.net` names
- Supports egress proxy patterns (calling external Tailscale services)
- Allows ingress workloads to reference their own MagicDNS names (callback scenarios)

**Cons**:
- Additional complexity (DNSConfig CRD, nameserver deployment, ConfigMap management)
- Requires manual CoreDNS ConfigMap updates (not automated by operator)
- Increases DNS query latency for `*.ts.net` lookups

**When to use**:
- Service mesh integration (Linkerd, Istio calling Tailscale services)
- Egress proxies (cluster workloads accessing external Tailscale-only services)
- Callback scenarios (ingress pods referring to their own MagicDNS URL)

---

## Rationale

### Why No CoreDNS Changes for Basic API Access?

1. **DNS Resolution Happens Client-Side**: When a user runs `kubectl get nodes` from their Mac, the DNS query for `kind-operator-7.tail286401.ts.net` is resolved by the **Mac's DNS resolver**, not by CoreDNS inside the cluster. The Mac queries Tailscale MagicDNS (100.100.100.100) and receives the operator's Tailscale IP (100.x.x.x). The kubectl TCP connection goes directly to that IP.

2. **No Pod-to-API-Proxy Use Case**: The Tailscale operator's in-process API proxy is designed for **external clients** (kubectl from laptops, CI/CD systems). Pods inside the cluster that need API access use the standard `kubernetes.default.svc` endpoint (ClusterIP), not the Tailscale hostname.

3. **Operator Pod Doesn't Query DNS**: The API proxy runs inside the operator pod and forwards requests to `https://kubernetes.default.svc:443` using Kubernetes service discovery. No DNS lookup for `*.ts.net` names occurs within the cluster.

4. **Consistent with idpBuilder Pattern**: idpBuilder's CoreDNS rewrite rules (e.g., `gitea.cnoe.localtest.me` → `ingress-nginx-controller.svc`) solve a different problem: external domains (`.localtest.me`) that resolve to `127.0.0.1` externally but need in-cluster service resolution internally. Tailscale MagicDNS names don't have this issue because they resolve to routable Tailscale IPs both inside and outside the cluster.

### Why DNSConfig is Optional

From Tailscale CRD documentation (`cdk8s/crds/tailscale-crds.yaml`):

> DNSConfig can be deployed to cluster to make a subset of Tailscale MagicDNS names resolvable by cluster workloads. Use this if: A) you need to refer to tailnet services, exposed to cluster via Tailscale Kubernetes operator egress proxies by the MagicDNS names of those tailnet services (usually because the services run over HTTPS) B) you have exposed a cluster workload to the tailnet using Tailscale Ingress and you also want to refer to the workload from within the cluster over the Ingress's MagicDNS name (usually because you have some callback component that needs to use the same URL as that used by a non-cluster client on tailnet).

**Key Insight**: DNSConfig is for **egress proxies** and **ingress callbacks**, not for API server proxy access.

---

## Alternatives Considered

### Alternative 1: CoreDNS Rewrite Rule (Similar to ingress-nginx)

**Rejected**: Rewrite rules only work when you want to redirect a hostname to a **different service**. For example:

```conf
rewrite name gitea.cnoe.localtest.me ingress-nginx-controller.ingress-nginx.svc.cluster.local
```

This works because `gitea.cnoe.localtest.me` externally resolves to `127.0.0.1` (unusable from pods), so CoreDNS rewrites it to the ingress-nginx service IP.

For Tailscale, `kind-operator-7.tail286401.ts.net` resolves to a valid Tailscale IP (`100.x.x.x`) that is **already routable** from both inside and outside the cluster (if nodes have Tailscale). There's no need to rewrite to a different service because:
- External clients connect directly to `100.x.x.x:443` (operator pod)
- Internal pods use `kubernetes.default.svc:443` (not Tailscale hostname)

### Alternative 2: Manually Add Stub Zone Without DNSConfig

**Rejected**: You could manually add a CoreDNS stub zone for `ts.net` forwarding to Tailscale MagicDNS (100.100.100.100):

```conf
ts.net:53 {
    forward . 100.100.100.100
}
```

**Problems**:
- MagicDNS IP (100.100.100.100) is not routable from cluster nodes unless they're Tailscale clients
- Even if nodes have Tailscale, this bypasses the k8s-nameserver which provides operator-managed DNS records for in-cluster proxies
- Violates DNSConfig design: operator should manage MagicDNS resolution, not manual forwarding

### Alternative 3: Deploy DNSConfig by Default

**Rejected for MVP**: Adding DNSConfig increases complexity for a feature that isn't required for the primary use cases (kubectl access, port-forward, web UI). The spec explicitly states "resolve cluster service hostnames" (FR-007), not "resolve Tailscale hostnames from inside cluster".

**Future Enhancement**: If users need egress proxy support (pods calling Tailscale services), DNSConfig can be added as an optional feature with clear documentation on when to enable it.

---

## Testing Plan

### Test 1: External DNS Resolution (Primary Use Case)

**From Mac (Tailscale-connected device)**:
```bash
# Test MagicDNS resolution
dig kind-operator-7.tail286401.ts.net
# Expected: A record with 100.x.x.x

# Test kubectl connectivity
kubectl --kubeconfig=remote-kubeconfig.yaml get nodes
# Expected: List of cluster nodes, <2 second response time
```

**Verification**: No CoreDNS queries should occur (confirm with CoreDNS logs: `kubectl logs -n kube-system -l k8s-app=kube-dns`)

### Test 2: Internal DNS Resolution (Optional Use Case)

**From debug pod inside cluster**:
```bash
# Without DNSConfig
kubectl run -it --rm debug --image=alpine --restart=Never -- sh
/ # nslookup kind-operator-7.tail286401.ts.net
# Expected: SERVFAIL or timeout (unless cluster node has Tailscale)

# With DNSConfig (future)
# Expected: Resolves to 100.x.x.x via Tailscale k8s-nameserver
```

### Test 3: CoreDNS Load Validation

**Check current ConfigMap**:
```bash
kubectl get configmap -n kube-system coredns-conf-custom -o yaml
# Expected: Placeholder comment, no ts.net rules
```

**Verify no performance impact**:
```bash
# Run 100 DNS queries from pod
kubectl run -it --rm dnstest --image=alpine --restart=Never -- sh -c \
  "for i in \$(seq 1 100); do nslookup kubernetes.default.svc; done"
# Expected: All queries succeed, no ts.net forwarding overhead
```

---

## Conclusion

**CoreDNS Requirements**: **No changes required** for basic Tailscale API server proxy access.

**Implementation**: Use default CoreDNS configuration with upstream forwarding. Tailscale MagicDNS handles hostname resolution on client devices (Mac, laptops).

**Rationale**: DNS resolution for `*.ts.net` names happens **outside the cluster** on the client machine making the kubectl request. CoreDNS is not involved in the API proxy workflow because:
1. External clients query Tailscale MagicDNS before connecting to cluster
2. Internal pods use `kubernetes.default.svc` endpoint, not Tailscale hostname
3. Operator pod forwards requests internally using Kubernetes service discovery

**Future Enhancement**: If use cases emerge requiring pods to resolve `*.ts.net` names (egress proxies, service mesh), deploy `DNSConfig` CRD and add CoreDNS stub zone forwarding to `coredns-conf-custom` ConfigMap. Document this as an optional advanced configuration.

**Related Decisions**:
- TLS Certificate Management: See `research-tls-certificates.md`
- RBAC Impersonation Patterns: See `research-rbac-impersonation.md`
- ProxyGroup Simplification: See `research-proxygroup-removal.md`

---

## References

- **idpBuilder CoreDNS Documentation**: `/home/vpittamp/stacks/docs/cnoe-overview.md` (lines 695-712)
  - Example rewrite rule: `rewrite name gitea.cnoe.localtest.me ingress-nginx-controller.ingress-nginx.svc.cluster.local`
  - Context: External domain resolving to `127.0.0.1` needs cluster service resolution

- **Tailscale DNSConfig CRD**: `/home/vpittamp/stacks/cdk8s/crds/tailscale-crds.yaml` (lines 340-500)
  - Use case: In-cluster workloads resolving MagicDNS names for egress proxies or ingress callbacks
  - Requires manual CoreDNS stub zone configuration after deployment

- **CoreDNS ConfigMap**: `kubectl get configmap -n kube-system coredns -o yaml`
  - Import statement: `import ../coredns-configs/*.conf`
  - Upstream forwarding: `forward . /etc/resolv.conf`

- **Kubernetes DNS Documentation**: https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/#configuration-of-stub-domain-and-upstream-nameserver-using-coredns
  - Stub zone pattern for forwarding specific domains to custom nameservers

- **Tailscale Operator Logs**: `kubectl logs -n tailscale deployment/tailscale-operator`
  - Current state: "DNSConfig does not exist, not creating DNS records"
  - Confirms DNSConfig is optional and not required for API proxy functionality
