"""Integration tests for Langfuse dashboard metrics.

Tests:
- Token usage tracking in Langfuse
- Generation metrics aggregation
- Session-based grouping
- Cost tracking support

Note: Uses mock Langfuse client for isolated testing.
"""

from datetime import datetime, timedelta
from typing import Any
from unittest.mock import MagicMock
from uuid import uuid4

import pytest

from src.common.models import TokenUsage


class MockLangfuseGeneration:
    """Mock Langfuse generation with usage tracking."""

    def __init__(
        self,
        name: str,
        model: str = "claude-3-opus-20240229",
        input_data: Any = None,
    ):
        self.id = str(uuid4())
        self.name = name
        self.model = model
        self.input = input_data
        self.output = None
        self.usage: TokenUsage = None
        self.ended = False
        self.start_time = datetime.utcnow()
        self.end_time = None
        self.metadata: dict = {}

    def end(
        self,
        output: Any = None,
        usage: dict = None,
        metadata: dict = None,
    ):
        """End the generation and record usage."""
        self.output = output
        self.end_time = datetime.utcnow()
        self.ended = True

        if usage:
            self.usage = TokenUsage(
                prompt_tokens=usage.get("input", usage.get("prompt_tokens", 0)),
                completion_tokens=usage.get("output", usage.get("completion_tokens", 0)),
                total_tokens=usage.get("total", usage.get("total_tokens", 0)),
            )

        if metadata:
            self.metadata.update(metadata)

    @property
    def duration_ms(self) -> int:
        """Calculate duration in milliseconds."""
        if self.end_time and self.start_time:
            return int((self.end_time - self.start_time).total_seconds() * 1000)
        return 0


class MockLangfuseMetricsClient:
    """Mock Langfuse client for metrics testing."""

    def __init__(self):
        self.traces: dict[str, dict] = {}
        self.generations: list[MockLangfuseGeneration] = []
        self.sessions: dict[str, list[str]] = {}

    def create_trace(
        self,
        name: str,
        session_id: str = None,
        metadata: dict = None,
    ) -> str:
        """Create a trace."""
        trace_id = str(uuid4())
        self.traces[trace_id] = {
            "id": trace_id,
            "name": name,
            "session_id": session_id,
            "metadata": metadata or {},
            "generations": [],
            "timestamp": datetime.utcnow(),
        }

        if session_id:
            if session_id not in self.sessions:
                self.sessions[session_id] = []
            self.sessions[session_id].append(trace_id)

        return trace_id

    def create_generation(
        self,
        trace_id: str,
        name: str,
        model: str = "claude-3-opus-20240229",
        input_data: Any = None,
    ) -> MockLangfuseGeneration:
        """Create a generation."""
        gen = MockLangfuseGeneration(name=name, model=model, input_data=input_data)
        self.generations.append(gen)

        if trace_id in self.traces:
            self.traces[trace_id]["generations"].append(gen)

        return gen

    # =========================================================================
    # Metrics Methods
    # =========================================================================

    def get_total_tokens(self) -> dict[str, int]:
        """Get total token usage across all generations."""
        prompt = sum(g.usage.prompt_tokens for g in self.generations if g.usage)
        completion = sum(g.usage.completion_tokens for g in self.generations if g.usage)
        total = sum(g.usage.total_tokens for g in self.generations if g.usage)

        return {
            "prompt_tokens": prompt,
            "completion_tokens": completion,
            "total_tokens": total,
        }

    def get_tokens_by_model(self) -> dict[str, dict[str, int]]:
        """Get token usage grouped by model."""
        by_model = {}

        for gen in self.generations:
            if not gen.usage:
                continue

            model = gen.model
            if model not in by_model:
                by_model[model] = {
                    "prompt_tokens": 0,
                    "completion_tokens": 0,
                    "total_tokens": 0,
                    "generation_count": 0,
                }

            by_model[model]["prompt_tokens"] += gen.usage.prompt_tokens
            by_model[model]["completion_tokens"] += gen.usage.completion_tokens
            by_model[model]["total_tokens"] += gen.usage.total_tokens
            by_model[model]["generation_count"] += 1

        return by_model

    def get_tokens_by_session(self, session_id: str) -> dict[str, int]:
        """Get token usage for a specific session."""
        if session_id not in self.sessions:
            return {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}

        trace_ids = self.sessions[session_id]
        prompt = 0
        completion = 0
        total = 0

        for trace_id in trace_ids:
            if trace_id not in self.traces:
                continue

            for gen in self.traces[trace_id]["generations"]:
                if gen.usage:
                    prompt += gen.usage.prompt_tokens
                    completion += gen.usage.completion_tokens
                    total += gen.usage.total_tokens

        return {
            "prompt_tokens": prompt,
            "completion_tokens": completion,
            "total_tokens": total,
        }

    def get_generation_stats(self) -> dict[str, Any]:
        """Get statistics about generations."""
        if not self.generations:
            return {
                "count": 0,
                "avg_duration_ms": 0,
                "avg_tokens": 0,
            }

        durations = [g.duration_ms for g in self.generations if g.ended]
        tokens = [g.usage.total_tokens for g in self.generations if g.usage]

        return {
            "count": len(self.generations),
            "avg_duration_ms": sum(durations) / len(durations) if durations else 0,
            "avg_tokens": sum(tokens) / len(tokens) if tokens else 0,
        }


class TestTokenUsageTracking:
    """Integration tests for token usage tracking."""

    @pytest.fixture
    def langfuse(self):
        return MockLangfuseMetricsClient()

    @pytest.mark.asyncio
    async def test_track_single_generation_usage(self, langfuse):
        """Should track token usage for a single generation."""
        trace_id = langfuse.create_trace("workflow", session_id="session-1")

        gen = langfuse.create_generation(
            trace_id=trace_id,
            name="specifier_generation",
            model="claude-3-opus-20240229",
        )

        gen.end(
            output="Generated specification",
            usage={"input": 1000, "output": 500, "total": 1500},
        )

        assert gen.usage.prompt_tokens == 1000
        assert gen.usage.completion_tokens == 500
        assert gen.usage.total_tokens == 1500

    @pytest.mark.asyncio
    async def test_track_multiple_generations(self, langfuse):
        """Should track usage across multiple generations."""
        trace_id = langfuse.create_trace("workflow", session_id="session-1")

        usages = [
            {"input": 500, "output": 200, "total": 700},
            {"input": 800, "output": 400, "total": 1200},
            {"input": 300, "output": 150, "total": 450},
        ]

        for i, usage in enumerate(usages):
            gen = langfuse.create_generation(
                trace_id=trace_id,
                name=f"generation_{i}",
            )
            gen.end(output=f"Result {i}", usage=usage)

        totals = langfuse.get_total_tokens()
        assert totals["prompt_tokens"] == 1600
        assert totals["completion_tokens"] == 750
        assert totals["total_tokens"] == 2350

    @pytest.mark.asyncio
    async def test_track_usage_by_model(self, langfuse):
        """Should track usage grouped by model."""
        trace_id = langfuse.create_trace("workflow")

        # Opus generations
        for _ in range(2):
            gen = langfuse.create_generation(
                trace_id=trace_id,
                name="opus_gen",
                model="claude-3-opus-20240229",
            )
            gen.end(usage={"input": 1000, "output": 500, "total": 1500})

        # Sonnet generations
        for _ in range(3):
            gen = langfuse.create_generation(
                trace_id=trace_id,
                name="sonnet_gen",
                model="claude-3-sonnet-20240229",
            )
            gen.end(usage={"input": 500, "output": 250, "total": 750})

        by_model = langfuse.get_tokens_by_model()

        assert by_model["claude-3-opus-20240229"]["total_tokens"] == 3000
        assert by_model["claude-3-opus-20240229"]["generation_count"] == 2

        assert by_model["claude-3-sonnet-20240229"]["total_tokens"] == 2250
        assert by_model["claude-3-sonnet-20240229"]["generation_count"] == 3


class TestSessionBasedMetrics:
    """Integration tests for session-based metrics."""

    @pytest.fixture
    def langfuse(self):
        return MockLangfuseMetricsClient()

    @pytest.mark.asyncio
    async def test_group_usage_by_session(self, langfuse):
        """Should group token usage by session (workflow)."""
        # Session 1 - workflow A
        trace1 = langfuse.create_trace("workflow_a", session_id="workflow-a")
        gen1 = langfuse.create_generation(trace_id=trace1, name="gen1")
        gen1.end(usage={"input": 500, "output": 250, "total": 750})

        gen2 = langfuse.create_generation(trace_id=trace1, name="gen2")
        gen2.end(usage={"input": 300, "output": 150, "total": 450})

        # Session 2 - workflow B
        trace2 = langfuse.create_trace("workflow_b", session_id="workflow-b")
        gen3 = langfuse.create_generation(trace_id=trace2, name="gen3")
        gen3.end(usage={"input": 1000, "output": 500, "total": 1500})

        # Check session totals
        session_a = langfuse.get_tokens_by_session("workflow-a")
        session_b = langfuse.get_tokens_by_session("workflow-b")

        assert session_a["total_tokens"] == 1200
        assert session_b["total_tokens"] == 1500

    @pytest.mark.asyncio
    async def test_multiple_traces_per_session(self, langfuse):
        """Should handle multiple traces in same session."""
        session_id = "multi-trace-session"

        # Multiple traces for same workflow (e.g., different phases)
        for phase in ["spec", "plan", "tasks"]:
            trace_id = langfuse.create_trace(
                name=f"phase_{phase}",
                session_id=session_id,
            )
            gen = langfuse.create_generation(
                trace_id=trace_id,
                name=f"{phase}_generation",
            )
            gen.end(usage={"input": 500, "output": 250, "total": 750})

        session_totals = langfuse.get_tokens_by_session(session_id)
        assert session_totals["total_tokens"] == 2250  # 750 * 3


class TestGenerationStatistics:
    """Integration tests for generation statistics."""

    @pytest.fixture
    def langfuse(self):
        return MockLangfuseMetricsClient()

    @pytest.mark.asyncio
    async def test_calculate_average_duration(self, langfuse):
        """Should calculate average generation duration."""
        trace_id = langfuse.create_trace("workflow")

        for i in range(5):
            gen = langfuse.create_generation(trace_id=trace_id, name=f"gen_{i}")
            gen.end(
                usage={"input": 100, "output": 50, "total": 150},
            )

        stats = langfuse.get_generation_stats()
        assert stats["count"] == 5
        # Duration depends on test execution time, just verify it's calculated
        assert "avg_duration_ms" in stats

    @pytest.mark.asyncio
    async def test_calculate_average_tokens(self, langfuse):
        """Should calculate average tokens per generation."""
        trace_id = langfuse.create_trace("workflow")

        usages = [
            {"input": 100, "output": 50, "total": 150},
            {"input": 200, "output": 100, "total": 300},
            {"input": 300, "output": 150, "total": 450},
        ]

        for i, usage in enumerate(usages):
            gen = langfuse.create_generation(trace_id=trace_id, name=f"gen_{i}")
            gen.end(usage=usage)

        stats = langfuse.get_generation_stats()
        assert stats["count"] == 3
        assert stats["avg_tokens"] == 300  # (150 + 300 + 450) / 3

    @pytest.mark.asyncio
    async def test_handle_empty_generations(self, langfuse):
        """Should handle case with no generations."""
        stats = langfuse.get_generation_stats()

        assert stats["count"] == 0
        assert stats["avg_duration_ms"] == 0
        assert stats["avg_tokens"] == 0


class TestWorkflowMetricsAggregation:
    """Integration tests for workflow-level metrics."""

    @pytest.fixture
    def langfuse(self):
        return MockLangfuseMetricsClient()

    @pytest.mark.asyncio
    async def test_aggregate_metrics_for_workflow(self, langfuse):
        """Should aggregate all metrics for a complete workflow."""
        workflow_id = str(uuid4())

        # Simulate all phases
        phases = [
            ("specification", 1, {"input": 700, "output": 350, "total": 1050}),
            ("planning", 3, {"input": 800, "output": 400, "total": 1200}),
            ("task_generation", 1, {"input": 400, "output": 200, "total": 600}),
            ("implementation", 5, {"input": 1000, "output": 500, "total": 1500}),
        ]

        for phase, count, usage in phases:
            trace_id = langfuse.create_trace(
                name=f"phase_{phase}",
                session_id=workflow_id,
            )

            for i in range(count):
                gen = langfuse.create_generation(
                    trace_id=trace_id,
                    name=f"{phase}_gen_{i}",
                )
                gen.end(usage=usage)

        # Get workflow totals
        totals = langfuse.get_tokens_by_session(workflow_id)

        # Expected: 1*1050 + 3*1200 + 1*600 + 5*1500 = 1050 + 3600 + 600 + 7500 = 12750
        assert totals["total_tokens"] == 12750

    @pytest.mark.asyncio
    async def test_aggregate_multiple_workflows(self, langfuse):
        """Should aggregate metrics across multiple workflows."""
        workflow_ids = [str(uuid4()) for _ in range(3)]

        for wf_id in workflow_ids:
            trace_id = langfuse.create_trace(name="workflow", session_id=wf_id)
            gen = langfuse.create_generation(trace_id=trace_id, name="gen")
            gen.end(usage={"input": 1000, "output": 500, "total": 1500})

        # Check each workflow
        for wf_id in workflow_ids:
            totals = langfuse.get_tokens_by_session(wf_id)
            assert totals["total_tokens"] == 1500

        # Check global totals
        global_totals = langfuse.get_total_tokens()
        assert global_totals["total_tokens"] == 4500  # 1500 * 3


class TestCostEstimation:
    """Integration tests for cost estimation support."""

    @pytest.fixture
    def langfuse(self):
        return MockLangfuseMetricsClient()

    @pytest.mark.asyncio
    async def test_calculate_workflow_cost(self, langfuse):
        """Should support cost calculation from token usage."""
        trace_id = langfuse.create_trace("workflow", session_id="cost-test")

        # Simulate workflow generations
        gen = langfuse.create_generation(
            trace_id=trace_id,
            name="main_generation",
            model="claude-3-opus-20240229",
        )
        gen.end(usage={"input": 10000, "output": 5000, "total": 15000})

        totals = langfuse.get_tokens_by_session("cost-test")

        # Calculate cost (Claude 3 Opus pricing)
        input_price = 15.0  # per 1M tokens
        output_price = 75.0  # per 1M tokens

        input_cost = (totals["prompt_tokens"] / 1_000_000) * input_price
        output_cost = (totals["completion_tokens"] / 1_000_000) * output_price
        total_cost = input_cost + output_cost

        assert input_cost == 0.15  # 10000 * 15 / 1M
        assert output_cost == 0.375  # 5000 * 75 / 1M
        assert total_cost == 0.525

    @pytest.mark.asyncio
    async def test_cost_by_model(self, langfuse):
        """Should support cost calculation by model."""
        trace_id = langfuse.create_trace("workflow")

        # Opus (expensive)
        opus_gen = langfuse.create_generation(
            trace_id=trace_id,
            name="opus",
            model="claude-3-opus-20240229",
        )
        opus_gen.end(usage={"input": 1000, "output": 500, "total": 1500})

        # Haiku (cheap)
        haiku_gen = langfuse.create_generation(
            trace_id=trace_id,
            name="haiku",
            model="claude-3-haiku-20240307",
        )
        haiku_gen.end(usage={"input": 1000, "output": 500, "total": 1500})

        by_model = langfuse.get_tokens_by_model()

        # Different pricing for different models
        model_prices = {
            "claude-3-opus-20240229": {"input": 15.0, "output": 75.0},
            "claude-3-haiku-20240307": {"input": 0.25, "output": 1.25},
        }

        costs = {}
        for model, usage in by_model.items():
            prices = model_prices.get(model, {"input": 0, "output": 0})
            input_cost = (usage["prompt_tokens"] / 1_000_000) * prices["input"]
            output_cost = (usage["completion_tokens"] / 1_000_000) * prices["output"]
            costs[model] = input_cost + output_cost

        # Opus cost: (1000*15 + 500*75)/1M = 0.0525
        assert costs["claude-3-opus-20240229"] == pytest.approx(0.0525, rel=0.01)

        # Haiku cost: (1000*0.25 + 500*1.25)/1M = 0.000875
        assert costs["claude-3-haiku-20240307"] == pytest.approx(0.000875, rel=0.01)
