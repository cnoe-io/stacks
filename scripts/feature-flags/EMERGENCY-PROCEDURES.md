# CAIPE Feature Flag Emergency Procedures

## Quick Reference: Emergency Agent Disable

### Disable All CAIPE Agents (Master Kill Switch)

```bash
# 1. Edit the flagd ConfigMap directly
kubectl edit configmap flagd-config -n feature-flags

# 2. Find "caipe-agents-enabled" and change defaultVariant from "on" to "off"
#    OR change state from "ENABLED" to "DISABLED"

# 3. Force flagd to reload (optional - file watcher picks up within ~30s)
kubectl rollout restart deployment/flagd -n feature-flags
```

### Disable Specific Agent

| Agent | Flag Key | Command |
|-------|----------|---------|
| ArgoCD | `caipe-agent-argocd` | Edit ConfigMap, set defaultVariant: "off" |
| GitHub | `caipe-agent-github` | Edit ConfigMap, set defaultVariant: "off" |
| Backstage | `caipe-agent-backstage` | Edit ConfigMap, set defaultVariant: "off" |

### Disable Backstage AgentForge UI

```bash
# Set backstage-agentforge-enabled defaultVariant to "off"
kubectl edit configmap flagd-config -n feature-flags
```

## Verification Commands

```bash
# Check current flag value
kubectl run check-flag --rm -i --restart=Never \
  --image=curlimages/curl:8.5.0 -n feature-flags -- \
  curl -s -X POST -H "Content-Type: application/json" \
  -d '{"context":{"targetingKey":"check"}}' \
  "http://flagd:8016/ofrep/v1/evaluate/flags/caipe-agents-enabled"

# Run full CAIPE flags test
bash scripts/feature-flags/test-caipe-flags.sh
```

## Propagation Timing

- **flagd file watcher**: Picks up ConfigMap changes within ~30 seconds
- **Force immediate reload**: `kubectl rollout restart deployment/flagd -n feature-flags`

## Recovery: Re-enable Agents

```bash
# Set defaultVariant back to "on" for the relevant flag(s)
kubectl edit configmap flagd-config -n feature-flags

# Verify
kubectl run verify-flag --rm -i --restart=Never \
  --image=curlimages/curl:8.5.0 -n feature-flags -- \
  curl -s -X POST -H "Content-Type: application/json" \
  -d '{"context":{"targetingKey":"verify"}}' \
  "http://flagd:8016/ofrep/v1/evaluate/flags/caipe-agents-enabled"
```

## Flag States Reference

| Flag | Default | Emergency Value |
|------|---------|-----------------|
| caipe-agents-enabled | on (true) | off (false) |
| caipe-agent-argocd | on (true) | off (false) |
| caipe-agent-github | on (true) | off (false) |
| caipe-agent-backstage | on (true) | off (false) |
| caipe-deep-orchestration | off (false) | off (false) |
| caipe-artifact-streaming | on (true) | off (false) |
| backstage-agentforge-enabled | on (true) | off (false) |
| langfuse-tracing-enabled | on (true) | off (false) |

## Rate Limiting (Non-Emergency Adjustments)

```bash
# Reduce rate limits to manage load
# caipe-rate-limit variants: low(20), standard(100), high(500), unlimited(-1)
# llm-token-limit variants: small(1024), standard(4096), large(8192), xlarge(16384)
# agent-timeout-seconds variants: short(30), standard(120), long(300), extended(600)
```
