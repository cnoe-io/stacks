# Feature Specification: SpecKit Agent Observability

**Feature ID:** 100-dapr-agent-speckit-observability
**Status:** Draft
**Created:** 2025-12-03
**Last Updated:** 2025-12-03

---

## Overview

### Problem Statement

Platform operators and developers using the SpecKit multi-agent workflow system currently have no visibility into:
- What conversations are happening between agents and the LLM
- How workflows progress through the specifier → planner → task-generator → implementer pipeline
- Where bottlenecks or failures occur in distributed agent interactions
- The full context of LLM prompts and responses for debugging and optimization

Without observability, debugging agent misbehavior requires manual log inspection across multiple pods, and there's no way to review completed workflow executions or understand why an agent made specific decisions.

### Proposed Solution

Implement a comprehensive observability solution for the SpecKit agent system consisting of two complementary components:

1. **Distributed Tracing (Jaeger)**: Capture service-to-service communication, pub/sub message flow, and workflow execution timelines across all agents
2. **LLM Conversation Tracking (Langfuse)**: Record all LLM interactions including prompts, responses, token usage, latency, and costs with session grouping for multi-turn agent conversations

Both services will be accessible via:
- Local ingress (domain-based routing consistent with existing services)
- Remote Tailscale access (following established patterns for other cluster services)

### Value Proposition

- **Debugging**: Quickly identify where and why agent workflows fail
- **Optimization**: Analyze LLM token usage and latency to optimize prompts
- **Auditability**: Complete record of all agent decisions and LLM interactions
- **Cost Tracking**: Monitor LLM API costs per workflow execution
- **Performance**: Identify bottlenecks in agent-to-agent communication

---

## User Scenarios & Testing

### Scenario 1: Debugging a Failed Workflow

**Actor:** Platform Developer

**Preconditions:**
- A SpecKit workflow was submitted but failed during the planning phase
- Developer needs to understand what went wrong

**Flow:**
1. Developer opens Jaeger UI
2. Developer searches for traces by workflow instance ID
3. Developer views the distributed trace showing all agent interactions
4. Developer identifies the failing span (planner agent → LLM call)
5. Developer clicks through to Langfuse to see the full LLM conversation
6. Developer sees the exact prompt sent and error response received
7. Developer identifies the issue (e.g., malformed input from specifier)

**Expected Outcome:** Developer can trace the exact failure point and root cause within 5 minutes

**Acceptance Criteria:**
- Traces are correlated across all agents in a workflow
- LLM calls are linked from Jaeger traces to Langfuse sessions
- Error spans are clearly highlighted in the UI

---

### Scenario 2: Reviewing Agent Conversation History

**Actor:** Platform Operator

**Preconditions:**
- Multiple workflows have completed successfully
- Operator wants to review how agents are using the LLM

**Flow:**
1. Operator opens Langfuse UI
2. Operator filters sessions by agent type (e.g., "specifier")
3. Operator selects a session to review
4. Operator sees the full multi-turn conversation with timestamps
5. Operator reviews token usage and latency metrics
6. Operator identifies optimization opportunities (verbose prompts, unnecessary retries)

**Expected Outcome:** Operator can review any agent's LLM usage and identify optimization opportunities

**Acceptance Criteria:**
- Sessions are grouped by workflow instance ID
- Each agent's conversations are separately identifiable
- Token usage and costs are displayed per session

---

### Scenario 3: Remote Access to Observability Dashboards

**Actor:** Off-site Developer

**Preconditions:**
- Developer is working remotely (not on cluster host)
- Developer has Tailscale access configured

**Flow:**
1. Developer connects to Tailscale network
2. Developer navigates to `https://jaeger.{tailscale-hostname}` in browser
3. Developer is presented with Jaeger UI (TLS secured)
4. Developer navigates to `https://langfuse.{tailscale-hostname}`
5. Developer authenticates with configured credentials
6. Developer can access both dashboards as if on local network

**Expected Outcome:** Remote access works identically to local access

**Acceptance Criteria:**
- Both services are exposed via Tailscale LoadBalancer
- TLS certificates are automatically provisioned
- No VPN or port-forwarding required

---

### Scenario 4: Monitoring Workflow Performance Over Time

**Actor:** Platform Operator

**Preconditions:**
- System has been running for several days
- Operator wants to identify performance trends

**Flow:**
1. Operator opens Jaeger UI
2. Operator views service dependency graph
3. Operator identifies average latency between agents
4. Operator compares current performance to baseline
5. Operator exports metrics for reporting

**Expected Outcome:** Operator can identify performance trends and degradation

**Acceptance Criteria:**
- Historical traces are retained for at least 7 days
- Service dependency graph is automatically generated
- Latency percentiles (p50, p95, p99) are visible

---

## Functional Requirements

### FR-1: Distributed Tracing with Jaeger

**Description:** Deploy Jaeger as the distributed tracing backend for all Dapr-enabled services

**Requirements:**
- FR-1.1: Jaeger collector receives traces from Dapr sidecars
- FR-1.2: Jaeger query service provides web UI for trace exploration
- FR-1.3: All SpecKit agents emit traces for inbound/outbound requests
- FR-1.4: Pub/sub message flow is captured in traces
- FR-1.5: Workflow state transitions are captured as spans
- FR-1.6: Trace sampling rate is configurable (default: 100% for development)

**Acceptance Criteria:**
- Every agent-to-agent interaction appears as connected spans
- Workflow instance ID is propagated as trace context
- UI loads and displays traces without errors

---

### FR-2: LLM Observability with Langfuse

**Description:** Deploy Langfuse for capturing and analyzing LLM interactions

**Requirements:**
- FR-2.1: Langfuse server stores all LLM call data
- FR-2.2: Each agent instruments LLM calls with Langfuse SDK
- FR-2.3: Sessions group related LLM calls by workflow instance
- FR-2.4: Token usage is captured for each generation
- FR-2.5: Latency is measured for each LLM call
- FR-2.6: Prompt and response content is fully captured
- FR-2.7: Agent name is tagged on each trace for filtering

**Acceptance Criteria:**
- All LLM calls appear in Langfuse within 30 seconds
- Sessions correctly group multi-turn conversations
- Token counts match actual API usage

---

### FR-3: Dapr Tracing Configuration

**Description:** Configure Dapr runtime to emit traces to Jaeger

**Requirements:**
- FR-3.1: Dapr Configuration resource enables tracing
- FR-3.2: Zipkin protocol sends traces to Jaeger collector
- FR-3.3: Sampling rate is set to capture all traces in development
- FR-3.4: W3C trace context headers are propagated between services
- FR-3.5: Configuration applies to all agents in dapr-agents namespace

**Acceptance Criteria:**
- Dapr sidecar logs show tracing enabled
- Traces appear in Jaeger within 5 seconds of request completion
- Trace IDs are consistent across service boundaries

---

### FR-4: Ingress Access (Local)

**Description:** Expose observability UIs via cluster ingress

**Requirements:**
- FR-4.1: Jaeger UI accessible at `jaeger.cnoe.localtest.me`
- FR-4.2: Langfuse UI accessible at `langfuse.cnoe.localtest.me`
- FR-4.3: Both use HTTPS with cluster TLS (consistent with other services)
- FR-4.4: Ingress uses nginx ingress class

**Acceptance Criteria:**
- `https://jaeger.cnoe.localtest.me:8443` loads Jaeger UI
- `https://langfuse.cnoe.localtest.me:8443` loads Langfuse UI
- TLS certificates are valid (self-signed acceptable for local dev)

---

### FR-5: Tailscale Remote Access

**Description:** Expose observability UIs via Tailscale for remote access

**Requirements:**
- FR-5.1: Jaeger exposed via Tailscale LoadBalancer service
- FR-5.2: Langfuse exposed via Tailscale LoadBalancer service
- FR-5.3: Services tagged with `tag:k8s` in Tailscale
- FR-5.4: Automatic Let's Encrypt certificates via Tailscale HTTPS
- FR-5.5: Services appear in Tailscale admin console

**Acceptance Criteria:**
- `https://jaeger.{tailnet-name}.ts.net` accessible from any Tailscale device
- `https://langfuse.{tailnet-name}.ts.net` accessible from any Tailscale device
- Connection works without port-forwarding or VPN tunnel configuration

---

### FR-6: Data Persistence

**Description:** Observability data is persisted for historical analysis

**Requirements:**
- FR-6.1: Jaeger uses persistent storage for trace data
- FR-6.2: Langfuse uses persistent storage for LLM interaction data
- FR-6.3: Data retention period is at least 7 days
- FR-6.4: Storage can be cleaned up without affecting running services

**Acceptance Criteria:**
- Traces from 7 days ago are retrievable
- LLM sessions from 7 days ago are viewable
- Pod restarts do not lose historical data

---

### FR-7: Agent Instrumentation

**Description:** SpecKit agents are instrumented to emit observability data

**Requirements:**
- FR-7.1: Each agent emits custom spans for key operations
- FR-7.2: LLM calls are wrapped with Langfuse tracing
- FR-7.3: Workflow instance ID is included in all telemetry
- FR-7.4: Agent name and role are tagged on all spans
- FR-7.5: Error states are properly captured and reported

**Acceptance Criteria:**
- Jaeger shows spans for: task_received, llm_call, task_completed
- Langfuse shows generations linked to specific agents
- Errors include stack traces and context

---

## Success Criteria

| Criterion | Target | Measurement Method |
|-----------|--------|-------------------|
| Trace visibility | 100% of agent interactions captured | Sample 10 workflows, verify all spans present |
| LLM capture rate | 100% of LLM calls recorded | Compare Langfuse count to agent logs |
| Debug time reduction | Find failure root cause in under 5 minutes | Timed debugging exercise |
| Remote access latency | UI loads in under 3 seconds | Measure from Tailscale-connected device |
| Data retention | 7 days of historical data | Query for week-old traces |
| Uptime | Observability services available 99% | Monitor over 1 week period |

---

## Scope

### In Scope

- Jaeger deployment and configuration
- Langfuse deployment and configuration
- Dapr tracing configuration
- Ingress resources for local access
- Tailscale LoadBalancer services for remote access
- Agent code instrumentation for Langfuse
- Persistent storage for both services
- CDK8s charts following existing patterns

### Out of Scope

- Alerting and notification systems
- Long-term metrics aggregation (Prometheus/Grafana)
- Log aggregation (ELK/Loki stack)
- Custom dashboards beyond default UIs
- Multi-cluster tracing correlation
- Cost optimization recommendations (manual analysis only)

---

## Dependencies

### Technical Dependencies

- **Dapr Runtime**: Must support tracing configuration (v1.16+ confirmed)
- **Tailscale Operator**: Required for remote access (already deployed)
- **Ingress Controller**: nginx ingress class (already deployed)
- **External Secrets**: For Langfuse database credentials (already deployed)

### External Dependencies

- **Azure Key Vault**: Store Langfuse secrets (database password, API keys)
- **Tailscale**: Network connectivity for remote access

---

## Assumptions

1. **Development Environment Focus**: Initial deployment targets the local Kind cluster; production HA is out of scope
2. **Single Namespace**: Both Jaeger and Langfuse will deploy to a new `observability` namespace
3. **Embedded Storage**: Jaeger will use Badger (embedded) storage rather than Elasticsearch/Cassandra for simplicity
4. **Langfuse Self-Hosted**: Using open-source self-hosted Langfuse, not cloud version
5. **PostgreSQL for Langfuse**: Langfuse requires PostgreSQL; a dedicated instance will be deployed
6. **100% Sampling**: All traces captured in development; production would use sampling
7. **Standard Retention**: 7-day retention is sufficient for development/debugging use cases
8. **Existing Tailscale Patterns**: Will follow `ingress-tailscale-publish-chart.ts` pattern for service exposure

---

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Storage exhaustion from high trace volume | Medium | High | Configure retention limits, monitor PVC usage |
| Performance impact from tracing overhead | Low | Medium | Sampling rate can be reduced if needed |
| Langfuse database corruption | Low | High | Regular backups, PVC snapshots |
| Tailscale rate limiting | Low | Low | Services are internal, minimal external traffic |

---

## Key Entities

### Trace

A distributed trace representing a complete workflow execution or agent interaction.

**Attributes:**
- Trace ID (unique identifier)
- Workflow Instance ID
- Service Name
- Operation Name
- Start Time
- Duration
- Status (OK/ERROR)
- Tags (agent_name, agent_role, task_type)

### LLM Generation

A single LLM API call captured by Langfuse.

**Attributes:**
- Generation ID
- Session ID (groups related calls)
- Trace ID (links to Jaeger)
- Agent Name
- Model Name
- Prompt Content
- Response Content
- Input Tokens
- Output Tokens
- Latency
- Cost (calculated)

### Session

A Langfuse session grouping related LLM calls.

**Attributes:**
- Session ID
- Workflow Instance ID
- User (agent name)
- Start Time
- End Time
- Total Tokens
- Total Cost

---

## Glossary

| Term | Definition |
|------|------------|
| **Span** | A single unit of work in a distributed trace |
| **Trace Context** | Headers (W3C standard) propagated between services to correlate spans |
| **Generation** | Langfuse term for a single LLM completion call |
| **Session** | Langfuse grouping of related generations |
| **Sampling Rate** | Percentage of requests that generate traces (0.0 to 1.0) |
| **Badger** | Embedded key-value store used by Jaeger for trace storage |
