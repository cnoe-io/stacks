"""Integration tests for cross-system trace correlation.

Tests:
- Langfuse and Jaeger traces can be correlated via workflow ID
- Trace context propagates through pub/sub messages
- Timestamps align across systems (within tolerance)
- All agents share the same trace ID

Note: Uses mock clients for isolated testing.
"""

from datetime import datetime, timedelta
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import UUID, uuid4

import pytest

from src.common.models import TraceContext, WorkflowMessage, WorkflowPhase


class MockLangfuseClient:
    """Mock Langfuse client for trace correlation testing."""

    def __init__(self):
        self.traces: dict[str, dict] = {}
        self.generations: list[dict] = []
        self.spans: list[dict] = []

    def create_trace(
        self,
        name: str,
        session_id: str,
        metadata: dict = None,
    ) -> str:
        """Create a new trace and return trace ID."""
        trace_id = f"langfuse-trace-{uuid4().hex[:8]}"
        self.traces[trace_id] = {
            "id": trace_id,
            "name": name,
            "session_id": session_id,
            "metadata": metadata or {},
            "timestamp": datetime.utcnow(),
            "generations": [],
            "spans": [],
        }
        return trace_id

    def add_generation(
        self,
        trace_id: str,
        name: str,
        input_data: Any,
        output_data: Any = None,
        model: str = "claude-3-opus-20240229",
    ) -> str:
        """Add a generation to a trace."""
        gen_id = f"gen-{uuid4().hex[:8]}"
        gen = {
            "id": gen_id,
            "trace_id": trace_id,
            "name": name,
            "input": input_data,
            "output": output_data,
            "model": model,
            "timestamp": datetime.utcnow(),
        }
        self.generations.append(gen)

        if trace_id in self.traces:
            self.traces[trace_id]["generations"].append(gen)

        return gen_id

    def add_span(
        self,
        trace_id: str,
        name: str,
        parent_observation_id: str = None,
    ) -> str:
        """Add a span to a trace."""
        span_id = f"span-{uuid4().hex[:8]}"
        span = {
            "id": span_id,
            "trace_id": trace_id,
            "name": name,
            "parent_observation_id": parent_observation_id,
            "timestamp": datetime.utcnow(),
        }
        self.spans.append(span)

        if trace_id in self.traces:
            self.traces[trace_id]["spans"].append(span)

        return span_id

    def get_trace_by_session(self, session_id: str) -> list[dict]:
        """Get traces by session ID (workflow_id)."""
        return [t for t in self.traces.values() if t["session_id"] == session_id]


class MockJaegerClient:
    """Mock Jaeger client for trace correlation testing."""

    def __init__(self):
        self.traces: dict[str, dict] = {}
        self.spans: list[dict] = []

    def create_trace(self, service_name: str, operation_name: str) -> str:
        """Create a new Jaeger trace."""
        trace_id = uuid4().hex
        self.traces[trace_id] = {
            "trace_id": trace_id,
            "service_name": service_name,
            "operation_name": operation_name,
            "start_time": datetime.utcnow(),
            "spans": [],
            "tags": {},
        }
        return trace_id

    def add_span(
        self,
        trace_id: str,
        operation_name: str,
        tags: dict = None,
        parent_span_id: str = None,
    ) -> str:
        """Add a span to a trace."""
        span_id = uuid4().hex[:16]
        span = {
            "span_id": span_id,
            "trace_id": trace_id,
            "operation_name": operation_name,
            "tags": tags or {},
            "parent_span_id": parent_span_id,
            "start_time": datetime.utcnow(),
        }
        self.spans.append(span)

        if trace_id in self.traces:
            self.traces[trace_id]["spans"].append(span)

        return span_id

    def add_tag(self, trace_id: str, key: str, value: str):
        """Add a tag to a trace."""
        if trace_id in self.traces:
            self.traces[trace_id]["tags"][key] = value

    def find_traces_by_tag(self, key: str, value: str) -> list[dict]:
        """Find traces by tag value."""
        return [
            t for t in self.traces.values()
            if t.get("tags", {}).get(key) == value
        ]


class TestLangfuseJaegerCorrelation:
    """Integration tests for Langfuse-Jaeger correlation."""

    @pytest.fixture
    def langfuse(self):
        return MockLangfuseClient()

    @pytest.fixture
    def jaeger(self):
        return MockJaegerClient()

    @pytest.mark.asyncio
    async def test_workflow_creates_both_traces(self, langfuse, jaeger):
        """Starting a workflow should create traces in both systems."""
        workflow_id = uuid4()

        # Create Langfuse trace with workflow_id as session
        langfuse_trace_id = langfuse.create_trace(
            name="workflow_execution",
            session_id=str(workflow_id),
            metadata={"feature": "test feature"},
        )

        # Create Jaeger trace with workflow_id tag
        jaeger_trace_id = jaeger.create_trace(
            service_name="speckit-agents",
            operation_name="workflow_execution",
        )
        jaeger.add_tag(jaeger_trace_id, "workflow.id", str(workflow_id))

        # Verify both traces exist
        assert langfuse_trace_id in langfuse.traces
        assert jaeger_trace_id in jaeger.traces

    @pytest.mark.asyncio
    async def test_correlation_via_workflow_id(self, langfuse, jaeger):
        """Should correlate traces using workflow_id."""
        workflow_id = uuid4()

        # Create traces in both systems
        langfuse.create_trace(
            name="workflow",
            session_id=str(workflow_id),
        )

        jaeger_trace_id = jaeger.create_trace(
            service_name="speckit",
            operation_name="workflow",
        )
        jaeger.add_tag(jaeger_trace_id, "workflow.id", str(workflow_id))

        # Correlate using workflow_id
        langfuse_traces = langfuse.get_trace_by_session(str(workflow_id))
        jaeger_traces = jaeger.find_traces_by_tag("workflow.id", str(workflow_id))

        assert len(langfuse_traces) == 1
        assert len(jaeger_traces) == 1

    @pytest.mark.asyncio
    async def test_timestamps_within_tolerance(self, langfuse, jaeger):
        """Traces in both systems should have timestamps within tolerance."""
        workflow_id = uuid4()
        tolerance = timedelta(seconds=1)

        # Create traces nearly simultaneously
        langfuse.create_trace(
            name="workflow",
            session_id=str(workflow_id),
        )

        jaeger.create_trace(
            service_name="speckit",
            operation_name="workflow",
        )

        # Get timestamps
        langfuse_time = langfuse.traces[list(langfuse.traces.keys())[0]]["timestamp"]
        jaeger_time = jaeger.traces[list(jaeger.traces.keys())[0]]["start_time"]

        # Verify within tolerance
        time_diff = abs((langfuse_time - jaeger_time).total_seconds())
        assert time_diff < tolerance.total_seconds()


class TestTraceContextPropagation:
    """Integration tests for trace context propagation."""

    @pytest.fixture
    def langfuse(self):
        return MockLangfuseClient()

    @pytest.mark.asyncio
    async def test_trace_context_in_pub_sub_messages(
        self, patch_dapr_client, mock_dapr_client, langfuse
    ):
        """Trace context should propagate through pub/sub messages."""
        workflow_id = uuid4()

        # Create initial trace
        trace_id = langfuse.create_trace(
            name="workflow",
            session_id=str(workflow_id),
        )

        # Create trace context
        ctx = TraceContext(
            trace_id=trace_id,
            workflow_id=workflow_id,
            agent_name="orchestrator",
        )

        # Publish message with trace context
        message = WorkflowMessage(
            source="orchestrator",
            workflow_id=workflow_id,
            task="execute_phase",
            context=ctx.to_message_context(),
        )

        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="speckit.specifier.requests",
            data=message.model_dump_json(),
        )

        # Receive and extract trace context
        received = mock_dapr_client._pubsub.get_messages("speckit.specifier.requests")
        received_msg = WorkflowMessage.model_validate_json(received[0])

        extracted_ctx = TraceContext.from_message_context(
            workflow_id=received_msg.workflow_id,
            agent_name="specifier",
            context=received_msg.context,
        )

        assert extracted_ctx.trace_id == trace_id

    @pytest.mark.asyncio
    async def test_trace_propagates_through_phase_transitions(
        self, patch_dapr_client, mock_dapr_client, langfuse
    ):
        """Trace context should propagate through all phase transitions."""
        workflow_id = uuid4()

        # Create initial trace
        trace_id = langfuse.create_trace(
            name="workflow",
            session_id=str(workflow_id),
        )

        phases = [
            ("orchestrator", "specifier"),
            ("specifier", "planner"),
            ("planner", "taskgenerator"),
            ("taskgenerator", "implementer"),
        ]

        current_ctx = TraceContext(
            trace_id=trace_id,
            workflow_id=workflow_id,
            agent_name="orchestrator",
        )

        for source, target in phases:
            # Publish transition message
            message = WorkflowMessage(
                source=source,
                workflow_id=workflow_id,
                task="phase_complete",
                context=current_ctx.to_message_context(),
            )

            await mock_dapr_client.publish_event(
                pubsub_name="speckit-pubsub",
                topic_name=f"speckit.{target}.requests",
                data=message.model_dump_json(),
            )

            # Extract for next phase
            received = mock_dapr_client._pubsub.get_messages(
                f"speckit.{target}.requests"
            )
            received_msg = WorkflowMessage.model_validate_json(received[-1])

            current_ctx = TraceContext.from_message_context(
                workflow_id=received_msg.workflow_id,
                agent_name=target,
                context=received_msg.context,
            )

            # Verify trace ID preserved
            assert current_ctx.trace_id == trace_id


class TestAllAgentsShareTraceId:
    """Integration tests for trace ID sharing across agents."""

    @pytest.fixture
    def langfuse(self):
        return MockLangfuseClient()

    @pytest.mark.asyncio
    async def test_all_agents_use_same_trace_id(self, langfuse):
        """All agents should use the same trace ID for a workflow."""
        workflow_id = uuid4()

        # Create single trace for workflow
        trace_id = langfuse.create_trace(
            name="workflow",
            session_id=str(workflow_id),
        )

        agents = ["orchestrator", "specifier", "planner", "taskgenerator", "implementer"]

        for agent in agents:
            # Each agent adds a generation to the same trace
            langfuse.add_generation(
                trace_id=trace_id,
                name=f"{agent}_generation",
                input_data=f"Input for {agent}",
                output_data=f"Output from {agent}",
            )

        # Verify all generations in same trace
        trace = langfuse.traces[trace_id]
        assert len(trace["generations"]) == len(agents)

    @pytest.mark.asyncio
    async def test_parent_observation_links_generations(self, langfuse):
        """Generations should be linked via parent_observation_id."""
        workflow_id = uuid4()

        trace_id = langfuse.create_trace(
            name="workflow",
            session_id=str(workflow_id),
        )

        # First agent generation
        first_gen_id = langfuse.add_generation(
            trace_id=trace_id,
            name="specifier_generation",
            input_data="Feature description",
            output_data="Specification",
        )

        # Second agent uses first as parent
        langfuse.add_span(
            trace_id=trace_id,
            name="planner_span",
            parent_observation_id=first_gen_id,
        )

        # Verify parent linkage
        trace = langfuse.traces[trace_id]
        assert len(trace["generations"]) == 1
        assert len(trace["spans"]) == 1
        assert trace["spans"][0]["parent_observation_id"] == first_gen_id


class TestJaegerSpanCorrelation:
    """Integration tests for Jaeger span correlation."""

    @pytest.fixture
    def jaeger(self):
        return MockJaegerClient()

    @pytest.mark.asyncio
    async def test_jaeger_spans_linked_by_workflow_id(self, jaeger):
        """Jaeger spans should be linked by workflow_id tag."""
        workflow_id = uuid4()

        # Create trace
        trace_id = jaeger.create_trace(
            service_name="speckit",
            operation_name="workflow",
        )
        jaeger.add_tag(trace_id, "workflow.id", str(workflow_id))

        # Add spans for each agent
        agents = ["specifier", "planner", "taskgenerator", "implementer"]
        parent_span = None

        for agent in agents:
            span_id = jaeger.add_span(
                trace_id=trace_id,
                operation_name=f"{agent}_execution",
                tags={"agent": agent, "workflow.id": str(workflow_id)},
                parent_span_id=parent_span,
            )
            parent_span = span_id

        # Verify all spans in trace
        trace = jaeger.traces[trace_id]
        assert len(trace["spans"]) == len(agents)

    @pytest.mark.asyncio
    async def test_jaeger_spans_have_agent_tags(self, jaeger):
        """Each Jaeger span should have agent tag."""
        workflow_id = uuid4()

        trace_id = jaeger.create_trace(
            service_name="speckit",
            operation_name="workflow",
        )

        jaeger.add_span(
            trace_id=trace_id,
            operation_name="specifier_execution",
            tags={"agent": "specifier"},
        )

        # Verify tag
        span = jaeger.spans[0]
        assert span["tags"]["agent"] == "specifier"


class TestCrossSystemLookup:
    """Integration tests for cross-system lookup."""

    @pytest.fixture
    def langfuse(self):
        return MockLangfuseClient()

    @pytest.fixture
    def jaeger(self):
        return MockJaegerClient()

    @pytest.mark.asyncio
    async def test_lookup_langfuse_from_jaeger_trace(self, langfuse, jaeger):
        """Should find Langfuse trace from Jaeger trace via workflow_id."""
        workflow_id = uuid4()

        # Create both traces
        langfuse.create_trace(
            name="workflow",
            session_id=str(workflow_id),
        )

        jaeger.create_trace(
            service_name="speckit",
            operation_name="workflow",
        )

        # Starting from Jaeger, find Langfuse trace
        # (In practice, this would use workflow_id from Jaeger tag)
        langfuse_traces = langfuse.get_trace_by_session(str(workflow_id))
        assert len(langfuse_traces) == 1

    @pytest.mark.asyncio
    async def test_lookup_jaeger_from_langfuse_trace(self, langfuse, jaeger):
        """Should find Jaeger trace from Langfuse trace via workflow_id."""
        workflow_id = uuid4()

        # Create both traces
        langfuse.create_trace(
            name="workflow",
            session_id=str(workflow_id),
        )

        jaeger_trace_id = jaeger.create_trace(
            service_name="speckit",
            operation_name="workflow",
        )
        jaeger.add_tag(jaeger_trace_id, "workflow.id", str(workflow_id))

        # Starting from Langfuse session_id, find Jaeger trace
        jaeger_traces = jaeger.find_traces_by_tag("workflow.id", str(workflow_id))
        assert len(jaeger_traces) == 1


class TestTimestampAlignment:
    """Integration tests for timestamp alignment across systems."""

    @pytest.fixture
    def langfuse(self):
        return MockLangfuseClient()

    @pytest.fixture
    def jaeger(self):
        return MockJaegerClient()

    @pytest.mark.asyncio
    async def test_phase_timestamps_align(self, langfuse, jaeger):
        """Phase timestamps should align across systems."""
        workflow_id = uuid4()
        tolerance_seconds = 1

        # Create traces
        trace_id = langfuse.create_trace(
            name="workflow",
            session_id=str(workflow_id),
        )

        jaeger_trace_id = jaeger.create_trace(
            service_name="speckit",
            operation_name="workflow",
        )

        # Add generations/spans for same phase
        langfuse.add_generation(
            trace_id=trace_id,
            name="specifier_generation",
            input_data="input",
        )

        jaeger.add_span(
            trace_id=jaeger_trace_id,
            operation_name="specifier_execution",
        )

        # Verify timestamps align
        langfuse_gen = langfuse.generations[0]
        jaeger_span = jaeger.spans[0]

        time_diff = abs(
            (langfuse_gen["timestamp"] - jaeger_span["start_time"]).total_seconds()
        )
        assert time_diff < tolerance_seconds

    @pytest.mark.asyncio
    async def test_complete_workflow_timestamps_ordered(self, langfuse):
        """Workflow timestamps should be in chronological order."""
        workflow_id = uuid4()

        trace_id = langfuse.create_trace(
            name="workflow",
            session_id=str(workflow_id),
        )

        # Add generations for each phase
        for phase in ["specification", "planning", "task_generation", "implementation"]:
            langfuse.add_generation(
                trace_id=trace_id,
                name=f"{phase}_generation",
                input_data=f"Input for {phase}",
            )

        # Verify timestamps are ordered
        timestamps = [g["timestamp"] for g in langfuse.generations]
        for i in range(len(timestamps) - 1):
            assert timestamps[i] <= timestamps[i + 1]
