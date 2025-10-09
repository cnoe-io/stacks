# Tasks: Kubernetes-Native AI Agent Platform (kagent & kmcp)

**Input**: Design documents from `/specs/001-review-docs-kagent/`
**Prerequisites**: plan.md, spec.md, data-model.md, contracts/, research.md, quickstart.md

**Tests**: Not explicitly requested in specification - focus on implementation tasks with validation steps

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions
- **CDK8s Charts**: `cdk8s/charts/infra/` (platform), `cdk8s/charts/apps/` (agents)
- **Shared Helpers**: `cdk8s/lib/`
- **CRD Imports**: `cdk8s/imports/`
- **Configuration**: `cdk8s/config/applications.ts`
- **Synthesized Output**: `cdk8s/dist/<app>/manifests/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and CRD imports required by all user stories

- [X] T001 [P] Import kagent Agent CRD types using `cdk8s import https://raw.githubusercontent.com/kagent-dev/kagent/main/deploy/crds/kagent.dev_agents.yaml` → generates `cdk8s/imports/kagent.dev.ts`
- [X] T002 [P] Import kagent ModelConfig CRD types using `cdk8s import https://raw.githubusercontent.com/kagent-dev/kagent/main/deploy/crds/kagent.dev_modelconfigs.yaml` → updates `cdk8s/imports/kagent.dev.ts`
- [X] T003 [P] Import kmcp MCPServer CRD types using Helm template from kmcp-crds chart → updates `cdk8s/imports/kagent.dev.ts` (MCPServer is part of kagent.dev API group)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 [P] Create helper functions for sync wave annotations in `cdk8s/lib/kagent-helpers.ts` (kagent-specific sync waves: CRDs=-110, Namespace=-100, RBAC=-90, Secrets=-70, Controllers=0, Agents=50)
- [X] T005 [P] Create helper functions for SecurityContext generation in `cdk8s/lib/kagent-helpers.ts` (runAsNonRoot, allowPrivilegeEscalation, readOnlyRootFilesystem)
- [X] T006 [P] Create helper functions for resource limits in `cdk8s/lib/kagent-helpers.ts` (controller: 500MB/250MB, engine: 1GB/512MB, mcp: 512MB/256MB)
- [X] T007 Create kustomization generator for kagent packages in `cdk8s/lib/kustomization-generator.ts` (already exists and supports all packages)
- [X] T008 Register KagentChart (auto-registered via auto-register-charts.ts)
- [X] T009 Register KmcpChart (auto-registered via auto-register-charts.ts)
- [X] T010 Register KagentExampleAgentsChart (auto-registered via auto-register-charts.ts)
- [X] T011 Register KagentSecretsChart (auto-registered via auto-register-charts.ts)

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Deploy AI Agent Infrastructure (Priority: P1) 🎯 MVP

**Goal**: Deploy kagent/kmcp controllers, CRDs, and supporting infrastructure to enable agent creation

**Independent Test**: Deploy kagent and kmcp packages, verify all controller pods are Running, access dashboard at http://localhost:8082, verify CRDs installed (`kubectl get crds | grep -E 'kagent|kmcp'`)

### Implementation for User Story 1

**Sub-Phase 3.1: kagent Platform Chart**

- [X] T012 [US1] Create KagentChart class in `cdk8s/charts/infra/kagent-chart.ts` extending Chart
- [X] T013 [P] [US1] Define kagent namespace resource in `kagent-chart.ts` using KubeNamespace (name: 'kagent', sync-wave: -100)
- [X] T014 [P] [US1] Define kagent Agent CRD resource in `kagent-chart.ts` using imported types from `cdk8s/imports/kagent.dev.ts` (sync-wave: -110)
- [X] T015 [P] [US1] Define kagent ModelConfig CRD resource in `kagent-chart.ts` using imported types (sync-wave: -110)
- [X] T016 [P] [US1] Define kagent RemoteMCPServer CRD resource in `kagent-chart.ts` using imported types (sync-wave: -110)
- [X] T017 [P] [US1] Create kagent-controller ServiceAccount in `kagent-chart.ts` (sync-wave: -90)
- [X] T018 [P] [US1] Create kagent-controller ClusterRole in `kagent-chart.ts` with permissions: agents/*, modelconfigs/*, pods/*, services/*, deployments/* (sync-wave: -90)
- [X] T019 [US1] Create kagent-controller ClusterRoleBinding in `kagent-chart.ts` linking ServiceAccount to ClusterRole (sync-wave: -90, depends on T017 and T018)
- [X] T020 [P] [US1] Create kagent-controller Deployment in `kagent-chart.ts` (image: ghcr.io/kagent-dev/kagent/controller:latest, resources: 500MB/250MB, SecurityContext from helper, sync-wave: 0)
- [X] T021 [P] [US1] Create kagent-app Deployment (engine) in `kagent-chart.ts` (image: ghcr.io/kagent-dev/kagent/app:latest, resources: 1GB/512MB, SecurityContext, sync-wave: 0)
- [X] T022 [P] [US1] Create kagent-dashboard Deployment in `kagent-chart.ts` (image: ghcr.io/kagent-dev/kagent/dashboard:latest, resources: 512MB/256MB, port: 8082, sync-wave: 0)
- [X] T023 [P] [US1] Create kagent-controller Service in `kagent-chart.ts` (ClusterIP, port: 8083 for A2A protocol, sync-wave: 0)
- [X] T024 [P] [US1] Create kagent-dashboard Service in `kagent-chart.ts` (ClusterIP, port: 8082, sync-wave: 0)
- [X] T025 [US1] Create kagent-dashboard Ingress in `kagent-chart.ts` (path: /kagent-dashboard, nginx.ingress.kubernetes.io/rewrite-target, sync-wave: 100)
- [X] T026 [US1] Add kagent application config to `cdk8s/config/applications.ts` (name: 'kagent', namespace: 'kagent', chart: {type: 'KagentChart'}, argocd: {syncWave: '-110', syncPolicy: {automated: {prune: true, selfHeal: true}}})

**Sub-Phase 3.2: kmcp Platform Chart**

- [X] T027 [US1] Create KmcpChart class in `cdk8s/charts/infra/kmcp-chart.ts` extending Chart
- [X] T028 [P] [US1] Define kmcp MCPServer CRD resource in `kmcp-chart.ts` using imported types from `cdk8s/imports/kmcp.dev.ts` (sync-wave: -110)
- [X] T029 [P] [US1] Create kmcp-controller ServiceAccount in `kmcp-chart.ts` (namespace: kagent, sync-wave: -90)
- [X] T030 [P] [US1] Create kmcp-controller ClusterRole in `kmcp-chart.ts` with permissions: mcpservers/*, pods/*, deployments/*, services/* (sync-wave: -90)
- [X] T031 [US1] Create kmcp-controller ClusterRoleBinding in `kmcp-chart.ts` linking ServiceAccount to ClusterRole (sync-wave: -90, depends on T029 and T030)
- [X] T032 [US1] Create kmcp-controller Deployment in `kmcp-chart.ts` (image: ghcr.io/kagent-dev/kmcp/controller:latest, resources: 500MB/250MB, SecurityContext, sync-wave: 0)
- [X] T033 [US1] Add kmcp application config to `cdk8s/config/applications.ts` (name: 'kmcp', namespace: 'kagent', chart: {type: 'KmcpChart'}, argocd: {syncWave: '-110', syncPolicy: {automated: {prune: true, selfHeal: true}}})

**Sub-Phase 3.3: External Secrets for LLM API Keys**

- [X] T034 [US1] Create KagentSecretsChart class in `cdk8s/charts/infra/kagent-secrets-chart.ts` extending Chart
- [X] T035 [US1] Create ExternalSecret resource in `kagent-secrets-chart.ts` (name: kagent-llm-providers, namespace: kagent, secretStoreRef: azure-keyvault-store, sync-wave: -70)
- [X] T036 [US1] Define secret data mappings in ExternalSecret: openai_api_key → OPENAI_API_KEY, anthropic_api_key → ANTHROPIC_API_KEY, gemini_api_key → GEMINI_API_KEY (remoteRefs to llm-providers/openai, llm-providers/anthropic, llm-providers/gemini)
- [X] T037 [US1] Add kagent-secrets application config to `cdk8s/config/applications.ts` (name: 'kagent-secrets', namespace: 'kagent', chart: {type: 'KagentSecretsChart'}, argocd: {syncWave: '-70'})

**Sub-Phase 3.4: Synthesis and Deployment Validation**

- [X] T038 [US1] Run `npx ts-node main-v2.ts` to synthesize kagent, kmcp, and kagent-secrets packages
- [X] T039 [US1] Verify synthesized manifests in `cdk8s/dist/kagent/manifests/`, `cdk8s/dist/kmcp/manifests/`, `cdk8s/dist/kagent-secrets/manifests/`
- [X] T040 [US1] Deploy kagent package using `idpbuilder create --package cdk8s/dist/kagent`
- [X] T041 [US1] Deploy kmcp package using `idpbuilder create --package cdk8s/dist/kmcp`
- [X] T042 [US1] Deploy kagent-secrets package using `idpbuilder create --package cdk8s/dist/kagent-secrets`
- [X] T043 [US1] Verify all pods Running: `kubectl wait --for=condition=ready pod -l app=kagent-controller -n kagent --timeout=300s`
- [X] T044 [US1] Verify CRDs installed: `kubectl get crds | grep -E 'agents.kagent|modelconfigs.kagent|mcpservers.kmcp'`
- [X] T045 [US1] Verify ExternalSecret synced: `kubectl get externalsecret kagent-llm-providers -n kagent -o jsonpath='{.status.conditions[0].status}'` (expect: True)
- [X] T046 [US1] Access dashboard via port-forward: `kubectl port-forward -n kagent svc/kagent-dashboard 8082:8082` and verify http://localhost:8082 loads

**Checkpoint**: At this point, User Story 1 should be fully functional - kagent/kmcp platform deployed, controllers running, dashboard accessible

---

## Phase 4: User Story 2 - Create and Deploy Custom AI Agents (Priority: P2)

**Goal**: Deploy example agents demonstrating Kubernetes resource queries and agent capabilities

**Independent Test**: Deploy kagent-agents package, verify agents are Running (`kubectl get agents -n kagent`), invoke k8s-agent to query deployments and verify accurate response

### Implementation for User Story 2

**Sub-Phase 4.1: Example Agents Chart Scaffold**

- [X] T047 [US2] Create KagentExampleAgentsChart class in `cdk8s/charts/apps/kagent-example-agents-chart.ts` extending Chart
- [X] T048 [P] [US2] Create helper function `createModelConfig` in `cdk8s/lib/kagent-helpers.ts` (params: name, namespace, provider, apiKeySecret, apiKeySecretKey, model) returning KubeModelConfig resource
- [X] T049 [P] [US2] Create helper function `createAgent` in `cdk8s/lib/kagent-helpers.ts` (params: name, namespace, description, systemMessage, tools[], modelConfig, a2aConfig?) returning KubeAgent resource

**Sub-Phase 4.2: ModelConfig Resource**

- [X] T050 [US2] Create default-model-config ModelConfig in `kagent-example-agents-chart.ts` using createModelConfig helper (provider: openAI, secret: kagent-llm-providers, key: OPENAI_API_KEY, model: gpt-4-turbo-preview, sync-wave: 0)

**Sub-Phase 4.3: k8s-agent (Kubernetes Query Agent)**

- [X] T051 [US2] Create k8s-agent Agent resource in `kagent-example-agents-chart.ts` using createAgent helper (description: "Kubernetes resource query agent", systemMessage: expertise in K8s operations, tools: [kagent-tool-server with k8s_get_resources, k8s_get_available_api_resources], modelConfig: default-model-config, sync-wave: 50)

**Sub-Phase 4.4: Synthesis and Agent Validation**

- [X] T052 [US2] Add kagent-agents application config to `cdk8s/config/applications.ts` (name: 'kagent-agents', namespace: 'kagent', chart: {type: 'KagentExampleAgentsChart'}, argocd: {syncWave: '50', syncPolicy: {automated: {prune: true, selfHeal: true}}})
- [X] T053 [US2] Run `npx ts-node main-v2.ts` to synthesize kagent-agents package
- [X] T054 [US2] Verify synthesized manifests in `cdk8s/dist/kagent-agents/manifests/` (expect: default-model-config.yaml, k8s-agent.yaml, kustomization.yaml)
- [X] T055 [US2] Deploy kagent-agents package using `idpbuilder create --package cdk8s/dist/kagent-agents`
- [X] T056 [US2] Verify agents deployed: `kubectl get agents -n kagent` (expect: k8s-agent with status Running)
- [X] T057 [US2] Verify agent pod running: `kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=agent -n kagent --timeout=300s`
- [X] T058 [US2] Test k8s-agent via port-forward: `kubectl port-forward -n kagent svc/kagent-controller 8083:8083` then `curl -X POST http://localhost:8083/api/v1/agents/kagent/k8s-agent/invoke -H "Content-Type: application/json" -d '{"prompt": "List all deployments in the kagent namespace"}'` (expect: agent lists kagent-controller, kagent-app, kmcp-controller)

**Checkpoint**: At this point, User Story 2 should be fully functional - agents can query Kubernetes resources and respond accurately

---

## Phase 5: User Story 3 - Deploy Custom MCP Tool Servers (Priority: P3)

**Goal**: Deploy custom MCP tool servers and agents that use them (web content fetcher example)

**Independent Test**: Deploy fetch-agent with mcp-website-fetcher MCPServer, verify tool server running, invoke fetch-agent to retrieve web content and verify successful fetch

### Implementation for User Story 3

**Sub-Phase 5.1: MCP Server Helpers**

- [X] T059 [P] [US3] Create helper function `createMCPServer` in `cdk8s/lib/mcp-tool-builders.ts` (params: name, namespace, cmd, args, port?, env?, secrets?) returning KubeMCPServer resource
- [X] T060 [P] [US3] Create helper function `createFastMCPServer` in `cdk8s/lib/mcp-tool-builders.ts` (params: name, namespace, packageName) wrapping createMCPServer with cmd: 'uvx', args: [packageName], transportType: 'stdio'

**Sub-Phase 5.2: MCP Website Fetcher Server**

- [X] T061 [US3] Create mcp-website-fetcher MCPServer resource in `kagent-example-agents-chart.ts` using createFastMCPServer helper (packageName: 'mcp-server-fetch', sync-wave: 0)

**Sub-Phase 5.3: fetch-agent (Web Content Agent)**

- [X] T062 [US3] Create fetch-agent Agent resource in `kagent-example-agents-chart.ts` using createAgent helper (description: "Agent that fetches and summarizes web content", systemMessage: research assistant using fetch tool, tools: [mcp-website-fetcher with fetch tool], modelConfig: default-model-config, sync-wave: 50)

**Sub-Phase 5.4: Synthesis and MCP Tool Validation**

- [X] T063 [US3] Run `npx ts-node main-v2.ts` to re-synthesize kagent-agents package with MCP server and fetch-agent
- [X] T064 [US3] Verify synthesized manifests updated in `cdk8s/dist/kagent-agents/manifests/` (expect: mcp-website-fetcher.yaml, fetch-agent.yaml added)
- [X] T065 [US3] Deploy updated kagent-agents package using `idpbuilder create --package cdk8s/dist/kagent-agents`
- [X] T066 [US3] Verify MCPServer deployed: `kubectl get mcpservers -n kagent` (expect: mcp-website-fetcher with status Running)
- [X] T067 [US3] Verify MCP server pod running: `kubectl get pods -n kagent -l app.kubernetes.io/component=mcp-server`
- [X] T068 [US3] Verify fetch-agent deployed: `kubectl get agents -n kagent` (expect: fetch-agent with status Running)
- [X] T069 [US3] Test fetch-agent: `curl -X POST http://localhost:8083/api/v1/agents/kagent/fetch-agent/invoke -H "Content-Type: application/json" -d '{"prompt": "Fetch and summarize content from https://kubernetes.io"}'` (expect: agent fetches and summarizes K8s homepage)

**Checkpoint**: At this point, User Story 3 should be fully functional - custom MCP tool servers deployed, agents using custom tools successfully

---

## Phase 6: User Story 4 - Enable Agent Interoperability (Priority: P4)

**Goal**: Enable A2A protocol on agents for external integrations (Slack, Discord, multi-agent workflows)

**Independent Test**: Deploy a2a-agent with A2A protocol enabled, query A2A capabilities endpoint, verify skills discoverable, invoke via A2A protocol and verify response

### Implementation for User Story 4

**Sub-Phase 6.1: A2A Protocol Helpers**

- [X] T070 [P] [US4] Create helper function `createA2AConfig` in `cdk8s/lib/kagent-helpers.ts` (params: skills[]) returning A2AConfig object with skill definitions (id, name, description, inputModes, outputModes, tags)
- [X] T071 [P] [US4] Create helper function `createA2ASkill` in `cdk8s/lib/kagent-helpers.ts` (params: id, name, description, tags[]) returning Skill object

**Sub-Phase 6.2: a2a-agent (A2A Protocol Enabled Agent)**

- [X] T072 [US4] Create A2A skill definition for get-resources-skill using createA2ASkill helper in `kagent-example-agents-chart.ts` (id: get-resources-skill, name: "Get Kubernetes Resources", tags: ['k8s', 'resources', 'query'])
- [X] T073 [US4] Create a2aConfig using createA2AConfig helper with get-resources-skill
- [X] T074 [US4] Create a2a-agent Agent resource in `kagent-example-agents-chart.ts` using createAgent helper (description: "Agent with A2A protocol enabled", systemMessage: K8s operations agent for programmatic access, tools: [kagent-tool-server with k8s tools], modelConfig: default-model-config, a2aConfig: from T073, sync-wave: 50)

**Sub-Phase 6.3: Synthesis and A2A Protocol Validation**

- [X] T075 [US4] Run `npx ts-node main-v2.ts` to re-synthesize kagent-agents package with a2a-agent
- [X] T076 [US4] Verify synthesized manifests updated in `cdk8s/dist/kagent-agents/manifests/` (expect: a2a-agent.yaml added)
- [X] T077 [US4] Deploy updated kagent-agents package using `idpbuilder create --package cdk8s/dist/kagent-agents`
- [X] T078 [US4] Verify a2a-agent deployed: `kubectl get agents -n kagent` (expect: a2a-agent with status Running)
- [X] T079 [US4] Query A2A capabilities endpoint: `curl http://localhost:8083/api/a2a/kagent/a2a-agent/.well-known/agent.json` (expect: JSON with skills, input/output modes, tags)
- [X] T080 [US4] Invoke a2a-agent via A2A protocol: `curl -X POST http://localhost:8083/api/a2a/kagent/a2a-agent/invoke -H "Content-Type: application/json" -d '{"skill_id": "get-resources-skill", "input": {"text": "Show me all services in kagent namespace"}}'` (expect: agent returns service list)

**Checkpoint**: At this point, User Story 4 should be fully functional - agents expose A2A protocol, discoverable by external systems

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and final validation

- [X] T081 [P] Add kagent/kmcp common commands to `CLAUDE.md` in "Common Commands" section (synthesis, deployment, testing, troubleshooting)
- [X] T082 [P] Add ArgoCD dashboard URLs for kagent applications to `CLAUDE.md` (kagent, kmcp, kagent-agents)
- [X] T083 [P] Document troubleshooting steps in `CLAUDE.md` (agents stuck pending, MCP server not discovered, LLM rate limits, ExternalSecret not syncing)
- [X] T084 [P] Run TypeScript compilation check: `cd cdk8s && npm run compile` (verify no errors)
- [X] T085 [P] Run manifest validation: `kubectl diff -f cdk8s/dist/kagent/manifests/` against cluster (verify no unexpected changes)
- [X] T086 Verify all ArgoCD applications synced: `argocd app list --insecure | grep kagent` (expect: kagent, kmcp, kagent-agents all Synced/Healthy)
- [X] T087 Run full end-to-end validation per quickstart.md instructions (deploy, verify, test all 3 agents)
- [X] T088 [P] Update `.cspell.json` or equivalent to add kagent/kmcp/fastmcp/ollama/mcps terms to dictionary (resolve spell check warnings)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational phase completion - BLOCKS US2, US3, US4
- **User Story 2 (Phase 4)**: Depends on US1 completion (requires platform deployed)
- **User Story 3 (Phase 5)**: Depends on US1 completion (requires platform deployed), can run in parallel with US2
- **User Story 4 (Phase 6)**: Depends on US1 completion (requires platform deployed), can run in parallel with US2/US3
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories - **MUST COMPLETE FIRST**
- **User Story 2 (P2)**: Can start after User Story 1 completion - Independent of US3/US4
- **User Story 3 (P3)**: Can start after User Story 1 completion - Can run in parallel with US2/US4
- **User Story 4 (P4)**: Can start after User Story 1 completion - Can run in parallel with US2/US3

### Within Each User Story

**User Story 1 (Platform Deployment)**:
- Sub-phases are mostly parallel: kagent chart (T012-T026), kmcp chart (T027-T033), secrets chart (T034-T037) can be built in parallel
- Synthesis (T038) depends on all chart implementation tasks
- Deployment tasks (T040-T046) must run sequentially (kagent → kmcp → kagent-secrets)

**User Story 2 (Agents)**:
- Helpers (T048-T049) before resources (T050-T051)
- ModelConfig (T050) before Agents (T051) - agents reference ModelConfig
- Synthesis (T053) after all resources defined

**User Story 3 (MCP Servers)**:
- Helpers (T059-T060) before resources (T061-T062)
- MCPServer (T061) before Agent (T062) - agent references MCPServer
- Synthesis (T063) after all resources defined

**User Story 4 (A2A Protocol)**:
- Helpers (T070-T071) before skill definition (T072) before config (T073) before agent (T074)
- Sequential flow for A2A configuration

### Parallel Opportunities

**Setup Phase**: All 3 CRD import tasks (T001-T003) can run in parallel

**Foundational Phase**: Helper functions (T004-T007) and chart registrations (T008-T011) can run in parallel

**User Story 1**:
- Charts can be built in parallel: kagent (T012-T026), kmcp (T027-T033), secrets (T034-T037)
- Within kagent chart: namespace (T013), CRDs (T014-T016), ServiceAccount (T017), ClusterRole (T018), Deployments (T020-T022), Services (T023-T024) can run in parallel
- Synthesis tasks (T038-T039) run together
- Deployment verification (T043-T046) can run in parallel

**User Story 2**:
- Helpers (T048-T049) run in parallel
- Synthesis verification (T054, T056-T057) run in parallel

**User Story 3**:
- Helpers (T059-T060) run in parallel
- Verification (T066-T068) run in parallel

**User Story 4**:
- Helpers (T070-T071) run in parallel

**Polish Phase**: Documentation tasks (T081-T083), validation tasks (T084-T085), spell check (T088) can run in parallel

---

## Parallel Example: User Story 1 (Platform Deployment)

```bash
# Phase 1: Setup - Launch all CRD imports together
Task T001: "Import kagent Agent CRD types"
Task T002: "Import kagent ModelConfig CRD types"
Task T003: "Import kmcp MCPServer CRD types"

# Phase 2: Foundational - Launch helper functions in parallel
Task T004: "Create sync wave helper functions"
Task T005: "Create SecurityContext helper functions"
Task T006: "Create resource limits helper functions"

# Phase 3: User Story 1 - Build charts in parallel
Task T013: "Define kagent namespace"
Task T014: "Define kagent Agent CRD"
Task T015: "Define kagent ModelConfig CRD"
Task T016: "Define kagent RemoteMCPServer CRD"
Task T017: "Create kagent-controller ServiceAccount"
Task T018: "Create kagent-controller ClusterRole"
# ... continue with parallel tasks

# Synthesis (sequential)
Task T038: "Synthesize all packages"

# Deployment verification (parallel)
Task T043: "Verify all pods Running"
Task T044: "Verify CRDs installed"
Task T045: "Verify ExternalSecret synced"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T011)
3. Complete Phase 3: User Story 1 (T012-T046)
4. **STOP and VALIDATE**: Verify kagent/kmcp platform deployed, controllers running, dashboard accessible
5. Deploy and demo User Story 1 completion

**MVP Deliverable**: Working kagent/kmcp platform with controllers, CRDs, dashboard, and secret management

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Deploy Platform → Test independently → **Deploy/Demo (MVP!)**
3. Add User Story 2 → Deploy Example Agents → Test k8s-agent → **Deploy/Demo**
4. Add User Story 3 → Deploy Custom MCP Servers → Test fetch-agent → **Deploy/Demo**
5. Add User Story 4 → Enable A2A Protocol → Test a2a-agent → **Deploy/Demo**
6. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (T001-T011)
2. Once User Story 1 is done (T012-T046):
   - Developer A: User Story 2 (T047-T058)
   - Developer B: User Story 3 (T059-T069)
   - Developer C: User Story 4 (T070-T080)
3. Stories complete and integrate independently
4. Reconvene for Polish (T081-T088)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
- **No tests included**: Specification did not explicitly request TDD or integration tests; validation steps included inline with deployment tasks
