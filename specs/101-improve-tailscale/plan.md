# Implementation Plan: Tailscale Services Migration

**Branch**: `101-improve-tailscale` | **Date**: 2025-12-04 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/101-improve-tailscale/spec.md`

## Summary

Migrate Tailscale service exposure from ephemeral device hostnames to stable Tailscale Services endpoints. This eliminates hostname suffix drift (`-1`, `-2`, etc.) on cluster recreation and provides consistent URLs for ArgoCD, Langfuse, and kubectl access.

**Technical Approach**: Update CDK8s charts to use `tailscale serve --service=svc:<name>` flag instead of device-hostname-based serving, with tag-based auth keys for automatic service approval.

## Technical Context

**Language/Version**: TypeScript (CDK8s charts)
**Primary Dependencies**: CDK8s, Tailscale v1.90.9+, Kubernetes
**Storage**: Azure Key Vault (auth key secret), Tailscale Admin Console (service definitions)
**Testing**: Manual verification (kubectl, curl), ArgoCD sync status
**Target Platform**: Kubernetes (Kind cluster, local development)
**Project Type**: Infrastructure-as-Code (CDK8s charts modification)
**Performance Goals**: Service URL resolution <30 seconds on pod startup
**Constraints**: TCP-only (Tailscale Services beta limitation), tag-based auth required
**Scale/Scope**: 3 services (ArgoCD, Langfuse, optional k8s-api)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

No constitution file present in repository. Proceeding with standard engineering best practices:

| Gate | Status | Notes |
|------|--------|-------|
| Single responsibility | PASS | Charts expose one service each |
| Backward compatibility | PASS | Legacy hostname mode preserved |
| Infrastructure as Code | PASS | All changes in CDK8s charts |
| Secret management | PASS | Auth key via Azure Key Vault |
| Documentation | PASS | Quickstart and research docs provided |

## Project Structure

### Documentation (this feature)

```
specs/101-improve-tailscale/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0: Tailscale Services research
├── data-model.md        # Phase 1: Entity definitions
├── quickstart.md        # Phase 1: Deployment guide
├── contracts/           # Phase 1: TypeScript interfaces
│   └── tailscale-serve-chart-props.ts
├── checklists/
│   └── requirements.md  # Specification quality checklist
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```
cdk8s/
├── charts/
│   └── platform/
│       ├── argocd-tailscale-serve-chart.ts    # UPDATE: Add --service flag
│       └── langfuse-tailscale-serve-chart.ts  # UPDATE: Add --service flag
├── lib/
│   └── tailscale-serve-helpers.ts             # NEW: Shared helper functions
└── config/
    └── applications.ts                         # UPDATE: Chart props

docs/
└── tailscale-services-migration.md            # NEW: Migration documentation
```

**Structure Decision**: Modify existing platform charts in `cdk8s/charts/platform/`. Add shared helper library for common Tailscale serve logic.

## Implementation Overview

### Phase 0: Research (Complete)

- [x] Tailscale Services availability confirmed (v1.86.0+, beta)
- [x] `--service` flag syntax documented
- [x] Tag-based auth key requirements confirmed
- [x] ACL auto-approver configuration documented
- [x] Beta limitations assessed (acceptable for use case)

See [research.md](./research.md) for full findings.

### Phase 1: Design (Complete)

- [x] Data model defined (service entities, chart props)
- [x] Contract interface created (TailscaleServeChartProps)
- [x] Quickstart guide written

See [data-model.md](./data-model.md) and [quickstart.md](./quickstart.md).

### Phase 2: Implementation Tasks (Pending)

To be generated via `/speckit.tasks`. High-level task breakdown:

#### Tailscale Admin Console (Manual, One-Time)

1. Create ACL tag `tag:k8s-services`
2. Define services: `svc:argocd-<cluster>`, `svc:langfuse-<cluster>`
3. Add ACL auto-approvers
4. Generate tagged auth key

#### Azure Key Vault

5. Update `tailscale-auth-key` secret with tagged key

#### CDK8s Charts

6. Create `lib/tailscale-serve-helpers.ts` with shared logic
7. Update `ArgoCdTailscaleServeChart` to use `--service` flag
8. Update `LangfuseTailscaleServeChart` to use `--service` flag
9. Add configurable props to `applications.ts`

#### Documentation

10. Create migration guide in `docs/`
11. Update CLAUDE.md with new service URLs

#### Testing

12. Deploy and verify service registration
13. Test cluster recreation for hostname stability

## Key Code Changes

### Before (Current)

```bash
# argocd-tailscale-serve-chart.ts (line 82)
tailscale serve --bg https+insecure://127.0.0.1:${PORT_FWD}
```

### After (With Tailscale Services)

```bash
# Updated command
tailscale serve --service=svc:argocd-<cluster> --https=443 https+insecure://127.0.0.1:${PORT_FWD}
```

### Chart Props Update

```typescript
// applications.ts
{
  name: 'argocd-tailscale-serve',
  namespace: 'tailscale',
  chart: {
    type: 'ArgoCdTailscaleServeChart',
    props: {
      serviceName: 'argocd',           // NEW
      backendHost: 'argocd-server.argocd.svc.cluster.local',
      backendPort: 443,
      backendInsecure: true
    }
  },
  // ...
}
```

## Complexity Tracking

No constitution violations requiring justification.

## Dependencies

| Dependency | Required For | Status |
|------------|--------------|--------|
| Tailscale v1.86.0+ | `--service` flag | Available (v1.90.9) |
| Tailscale Admin access | Service definitions | User responsibility |
| Azure Key Vault access | Secret update | User responsibility |
| External Secrets Operator | Secret sync | Deployed |

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Tailscale Services beta changes | Low | Medium | Pin to known-working Tailscale version |
| Auth key misconfiguration | Medium | High | Document exact steps, validate in quickstart |
| Service name conflicts | Low | Medium | Use unique names, document naming convention |

## Next Steps

1. Run `/speckit.tasks` to generate detailed implementation tasks
2. Complete Tailscale Admin Console setup (manual)
3. Update Azure Key Vault secret
4. Implement chart changes
5. Test and verify

## References

- [Tailscale Services Documentation](https://tailscale.com/kb/1552/tailscale-services)
- [Tailscale Serve Command](https://tailscale.com/kb/1242/tailscale-serve)
- [Services Configuration File](https://tailscale.com/kb/1589/tailscale-services-configuration-file)
- [Tailscale Services Blog](https://tailscale.com/blog/services-beta)
