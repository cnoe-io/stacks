"""SpecKit Agent Services.

This package contains cross-cutting services:
- tracing: OpenTelemetry/Jaeger distributed tracing
- state_manager: Workflow state CRUD operations
- tool_recorder: Langfuse tool invocation recording
- agent_registry: Agent registration and discovery
- auth_middleware: API authentication and rate limiting
- metrics: Prometheus metrics collection
- langfuse_client: Langfuse LLM observability client
- session_recovery: Session checkpoint and recovery
"""

from .tracing import (
    TracingService,
    get_tracing_service,
    inject_trace_context,
    extract_trace_context,
)
from .state_manager import StateManager, get_state_manager
from .tool_recorder import ToolRecorder, get_tool_recorder
from .agent_registry import (
    AgentRegistry,
    AgentInfo,
    AgentStatus,
    AgentCapability,
    AgentRegistration,
    HeartbeatRequest,
    get_agent_registry,
)
from .auth_middleware import (
    AuthMiddleware,
    AuthConfig,
    AuthScope,
    APIKeyStore,
    APIKeyInfo,
    require_scope,
    api_key_header,
)
from .metrics import (
    MetricsService,
    get_metrics_service,
    get_metrics_registry,
)
from .langfuse_client import (
    LangfuseClient,
    GenerationStatus,
    GenerationInfo,
    IncompleteGenerationInfo,
    get_langfuse_client,
)
from .workflow_queue import (
    WorkflowQueue,
    QueuedWorkflow,
    QueuePosition,
    QueueStatus,
    get_workflow_queue,
)
from .session_recovery import (
    SessionManager,
    Session,
    SessionState,
    Checkpoint,
    CheckpointType,
    RecoveryPlan,
    get_session_manager,
)

__all__ = [
    # Tracing
    "TracingService",
    "get_tracing_service",
    "inject_trace_context",
    "extract_trace_context",
    # State Management
    "StateManager",
    "get_state_manager",
    # Tool Recording
    "ToolRecorder",
    "get_tool_recorder",
    # Agent Registry
    "AgentRegistry",
    "AgentInfo",
    "AgentStatus",
    "AgentCapability",
    "AgentRegistration",
    "HeartbeatRequest",
    "get_agent_registry",
    # Auth Middleware
    "AuthMiddleware",
    "AuthConfig",
    "AuthScope",
    "APIKeyStore",
    "APIKeyInfo",
    "require_scope",
    "api_key_header",
    # Metrics
    "MetricsService",
    "get_metrics_service",
    "get_metrics_registry",
    # Langfuse Client
    "LangfuseClient",
    "GenerationStatus",
    "GenerationInfo",
    "IncompleteGenerationInfo",
    "get_langfuse_client",
    # Workflow Queue
    "WorkflowQueue",
    "QueuedWorkflow",
    "QueuePosition",
    "QueueStatus",
    "get_workflow_queue",
    # Session Recovery
    "SessionManager",
    "Session",
    "SessionState",
    "Checkpoint",
    "CheckpointType",
    "RecoveryPlan",
    "get_session_manager",
]
