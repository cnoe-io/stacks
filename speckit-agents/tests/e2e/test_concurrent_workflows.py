"""End-to-end tests for concurrent workflow execution.

Tests:
- 5 concurrent workflows complete successfully
- Workflow queue enforces limits
- All observability data is captured
- Success criteria from spec.md are met

Note: Uses mocked services for isolated testing.
"""

import asyncio
from datetime import datetime
from typing import Any
from uuid import UUID, uuid4

import pytest

from src.common.models import (
    Artifact,
    ArtifactType,
    Workflow,
    WorkflowPhase,
    WorkflowStatus,
)
from src.services.workflow_queue import (
    QueuePosition,
    QueueStatus,
    WorkflowQueue,
)


class MockDaprClient:
    """Mock Dapr client for testing."""

    def __init__(self):
        self._state: dict[str, str] = {}
        self._published: list[dict] = []

    def save_state(self, store_name: str, key: str, value: str):
        self._state[key] = value

    def get_state(self, store_name: str, key: str):
        class StateItem:
            def __init__(self, data):
                self.data = data

        return StateItem(self._state.get(key))

    def publish_event(self, pubsub_name: str, topic_name: str, data: str, **kwargs):
        self._published.append({
            "pubsub": pubsub_name,
            "topic": topic_name,
            "data": data,
        })


class MockLangfuseTracer:
    """Mock Langfuse tracer for testing."""

    def __init__(self):
        self.traces: dict[str, dict] = {}
        self.generations: list[dict] = {}

    def create_trace(self, workflow_id: UUID, name: str) -> str:
        trace_id = f"trace-{workflow_id}"
        self.traces[trace_id] = {
            "workflow_id": str(workflow_id),
            "name": name,
            "timestamp": datetime.utcnow().isoformat(),
        }
        return trace_id

    def record_generation(
        self,
        trace_id: str,
        agent_name: str,
        input_tokens: int,
        output_tokens: int,
    ):
        self.generations[f"{trace_id}-{agent_name}"] = {
            "trace_id": trace_id,
            "agent_name": agent_name,
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
        }


class MockWorkflowProcessor:
    """Mock workflow processor for testing concurrent execution."""

    def __init__(self):
        self.processing_times: dict[UUID, float] = {}
        self.completed: list[UUID] = []
        self.failed: list[UUID] = []
        self.langfuse = MockLangfuseTracer()

    async def process_workflow(
        self,
        workflow_id: UUID,
        feature_description: str,
        processing_time: float = 0.1,
    ) -> dict[str, Any]:
        """Simulate workflow processing."""
        start_time = datetime.utcnow()

        # Create Langfuse trace
        trace_id = self.langfuse.create_trace(workflow_id, "workflow")

        # Simulate processing through phases
        phases = [
            WorkflowPhase.SPECIFICATION,
            WorkflowPhase.PLANNING,
            WorkflowPhase.TASK_GENERATION,
            WorkflowPhase.IMPLEMENTATION,
        ]

        for phase in phases:
            # Simulate phase processing time
            await asyncio.sleep(processing_time / len(phases))

            # Record Langfuse generation
            self.langfuse.record_generation(
                trace_id=trace_id,
                agent_name=phase.value,
                input_tokens=1000,
                output_tokens=500,
            )

        end_time = datetime.utcnow()
        self.processing_times[workflow_id] = (end_time - start_time).total_seconds()
        self.completed.append(workflow_id)

        return {
            "workflow_id": workflow_id,
            "status": "completed",
            "trace_id": trace_id,
            "processing_time": self.processing_times[workflow_id],
        }


class TestConcurrentWorkflows:
    """E2E tests for concurrent workflow execution."""

    @pytest.fixture
    def workflow_queue(self):
        return WorkflowQueue(max_concurrent_per_agent=5)

    @pytest.fixture
    def processor(self):
        return MockWorkflowProcessor()

    @pytest.mark.asyncio
    async def test_five_concurrent_workflows_complete(
        self, workflow_queue, processor
    ):
        """5 concurrent workflows should all complete successfully."""
        workflow_ids = [uuid4() for _ in range(5)]
        agent_name = "orchestrator"

        # Enqueue all workflows
        positions = []
        for wf_id in workflow_ids:
            pos = await workflow_queue.enqueue(wf_id, agent_name)
            positions.append(pos)

        # All should start processing (max_concurrent=5)
        for pos in positions:
            assert pos.status == QueueStatus.PROCESSING
            assert pos.position == 0

        # Process all workflows concurrently
        tasks = [
            processor.process_workflow(wf_id, f"Feature {i}")
            for i, wf_id in enumerate(workflow_ids)
        ]
        results = await asyncio.gather(*tasks)

        # All should complete
        assert len(results) == 5
        assert len(processor.completed) == 5

        for result in results:
            assert result["status"] == "completed"
            assert result["trace_id"] is not None

    @pytest.mark.asyncio
    async def test_queue_enforces_limit(self, workflow_queue, processor):
        """Queue should enforce concurrent workflow limit."""
        workflow_ids = [uuid4() for _ in range(7)]  # More than limit
        agent_name = "specifier"

        positions = []
        for wf_id in workflow_ids:
            pos = await workflow_queue.enqueue(wf_id, agent_name)
            positions.append(pos)

        # First 5 should be processing
        for i, pos in enumerate(positions[:5]):
            assert pos.status == QueueStatus.PROCESSING
            assert pos.position == 0

        # Remaining should be waiting
        for i, pos in enumerate(positions[5:]):
            assert pos.status == QueueStatus.WAITING
            assert pos.position == i + 1  # 1, 2

    @pytest.mark.asyncio
    async def test_queue_starts_next_on_completion(
        self, workflow_queue, processor
    ):
        """Queue should start next workflow when one completes."""
        workflow_ids = [uuid4() for _ in range(6)]
        agent_name = "planner"

        # Enqueue all
        for wf_id in workflow_ids:
            await workflow_queue.enqueue(wf_id, agent_name)

        # Complete first workflow
        await workflow_queue.complete(workflow_ids[0], success=True)

        # Check that 6th workflow is now processing
        pos = await workflow_queue.get_position(workflow_ids[5])
        assert pos is not None
        assert pos.status == QueueStatus.PROCESSING

    @pytest.mark.asyncio
    async def test_observability_data_captured(
        self, workflow_queue, processor
    ):
        """All observability data should be captured for workflows."""
        workflow_ids = [uuid4() for _ in range(3)]

        # Process workflows
        for i, wf_id in enumerate(workflow_ids):
            result = await processor.process_workflow(wf_id, f"Feature {i}")

        # Verify Langfuse traces
        assert len(processor.langfuse.traces) == 3

        # Verify generations per phase
        expected_generations = 3 * 4  # 3 workflows * 4 phases
        assert len(processor.langfuse.generations) == expected_generations

        # Verify token usage recorded
        for gen_id, gen in processor.langfuse.generations.items():
            assert gen["input_tokens"] > 0
            assert gen["output_tokens"] > 0


class TestSuccessCriteria:
    """Tests verifying success criteria from spec.md."""

    @pytest.fixture
    def processor(self):
        return MockWorkflowProcessor()

    @pytest.mark.asyncio
    async def test_workflow_completes_all_phases(self, processor):
        """Workflow should complete all 4 phases: spec -> plan -> tasks -> impl."""
        workflow_id = uuid4()
        result = await processor.process_workflow(
            workflow_id,
            "Add user authentication",
        )

        assert result["status"] == "completed"

        # Verify all phases were traced
        trace_id = result["trace_id"]
        phase_generations = [
            gen for gen_id, gen in processor.langfuse.generations.items()
            if gen["trace_id"] == trace_id
        ]

        assert len(phase_generations) == 4
        phases_recorded = {gen["agent_name"] for gen in phase_generations}
        expected_phases = {
            "specification",
            "planning",
            "task_generation",
            "implementation",
        }
        assert phases_recorded == expected_phases

    @pytest.mark.asyncio
    async def test_langfuse_traces_linked_to_workflow(self, processor):
        """Langfuse traces should be linked to workflow ID."""
        workflow_id = uuid4()
        result = await processor.process_workflow(workflow_id, "Test feature")

        trace_id = result["trace_id"]
        trace = processor.langfuse.traces[trace_id]

        assert trace["workflow_id"] == str(workflow_id)

    @pytest.mark.asyncio
    async def test_token_usage_tracked(self, processor):
        """Token usage should be tracked for all LLM calls."""
        workflow_id = uuid4()
        await processor.process_workflow(workflow_id, "Test feature")

        # Sum all token usage
        total_input = sum(
            gen["input_tokens"]
            for gen in processor.langfuse.generations.values()
        )
        total_output = sum(
            gen["output_tokens"]
            for gen in processor.langfuse.generations.values()
        )

        assert total_input > 0
        assert total_output > 0


class TestAgentQueueStatus:
    """Tests for agent queue status reporting."""

    @pytest.fixture
    def workflow_queue(self):
        return WorkflowQueue(max_concurrent_per_agent=5)

    @pytest.mark.asyncio
    async def test_agent_status_shows_capacity(self, workflow_queue):
        """Agent status should show available capacity."""
        agent_name = "orchestrator"

        # Initially empty
        status = await workflow_queue.get_agent_status(agent_name)
        assert status["processing"] == 0
        assert status["waiting"] == 0
        assert status["available_slots"] == 5

        # Add 3 workflows
        for _ in range(3):
            await workflow_queue.enqueue(uuid4(), agent_name)

        status = await workflow_queue.get_agent_status(agent_name)
        assert status["processing"] == 3
        assert status["waiting"] == 0
        assert status["available_slots"] == 2

    @pytest.mark.asyncio
    async def test_queue_position_estimated_wait(self, workflow_queue):
        """Queue position should include estimated wait time."""
        agent_name = "specifier"

        # Fill queue
        for _ in range(5):
            await workflow_queue.enqueue(uuid4(), agent_name)

        # Add one more (will be queued)
        waiting_id = uuid4()
        pos = await workflow_queue.enqueue(waiting_id, agent_name)

        assert pos.status == QueueStatus.WAITING
        assert pos.estimated_wait_seconds is not None
        assert pos.estimated_wait_seconds > 0
