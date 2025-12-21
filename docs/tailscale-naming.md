# Tailscale Naming (Multi-Cluster, No Collisions)

When multiple Kubernetes clusters share a single tailnet, **Tailscale device names and service names must be unique**. Otherwise you’ll see:

- Service name collisions (multiple clusters advertising the same `svc:<name>`)
- Hostname collisions (`-1`, `-2`, … suffix drift)
- Confusing “which cluster am I hitting?” URLs

This repo standardizes naming so clusters can coexist safely.

## Cluster Identity

All cluster-scoped names derive from a single identifier:

- `CLUSTER_NAME` (**preferred**, deterministic for CI/GitOps)
- `CLUSTER_HOST` (legacy fallback; often the machine hostname for kind)

The value is normalized to a slug (lowercase, non-alphanumerics → `-`).

Examples:

- `CLUSTER_NAME=thinkpad`
- `CLUSTER_NAME=ryzen`
- `CLUSTER_NAME=hub`
- `CLUSTER_NAME=talos`

## Service Naming (Tailscale Services)

For anything exposed via **Tailscale Services** (`tailscale serve --service=svc:<name>`), the name is:

`<base>-<cluster>`

So the service registration becomes:

- `svc:<base>-<cluster>`

and the HTTPS URL becomes:

- `https://<base>-<cluster>.<tailnet>.ts.net`

Examples (cluster = `thinkpad`):

- ArgoCD UI: `svc:argocd-thinkpad` → `https://argocd-thinkpad.<tailnet>.ts.net`
- Grafana: `svc:grafana-thinkpad` → `https://grafana-thinkpad.<tailnet>.ts.net`
- K8s API proxy: `svc:k8s-api-thinkpad` → `https://k8s-api-thinkpad.<tailnet>.ts.net`

## Device Naming (Operator, Subnet Router, VMs)

Some components register as **devices** (not services). Those also need unique hostnames:

- Tailscale operator hostname: `<cluster>-operator`
- Subnet router hostname: `subnet-router-<cluster>`
- NixOS VM hostname (when enabled): `nixos-vm-<cluster>`

## Tailscale ACL Updates

Because service names are cluster-scoped, the **Tailscale ACL `autoApprovers.services` block must include the suffixed names**.

Add the tag and auto-approvers (Tailscale Admin Console → Access Controls):

```json
{
  "tagOwners": {
    "tag:k8s-services": ["autogroup:admin"]
  },
  "autoApprovers": {
    "services": {
      "svc:argocd-thinkpad": ["tag:k8s-services"],
      "svc:argocd-ryzen": ["tag:k8s-services"],
      "svc:k8s-api-thinkpad": ["tag:k8s-services"],
      "svc:k8s-api-ryzen": ["tag:k8s-services"]
    }
  }
}
```

Extend that list for each `<base>-<cluster>` service you expose (e.g., `grafana-<cluster>`, `otel-collector-<cluster>`, etc.).

## Required Admin Console Setup (Services)

ACLs alone do **not** create Tailscale Services. You must define each service once in:

- Tailscale Admin Console → **Services** (Beta)

Then the Kubernetes hosts (pods) advertising `svc:<name>` can be approved automatically by `autoApprovers.services`.

On Linux clients, you may need `sudo tailscale set --accept-routes=true` to learn the TailVIP routes for Services.

## Should Production Use Unsuffixed Names?

It’s possible to reserve unsuffixed names (e.g., `svc:argocd`) for a “primary” cluster by **not** setting `CLUSTER_NAME` and leaving `CLUSTER_HOST` empty during synthesis — but it’s easy to accidentally point at prod.

Recommendation:

- Prefer **always-suffixed** names for clarity and safety (`argocd-talos`, not `argocd`)
- If you do want a canonical alias, make it a deliberate exception and keep all other clusters strictly suffixed
