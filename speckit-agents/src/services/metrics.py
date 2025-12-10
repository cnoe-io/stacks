"""Prometheus metrics service for SpecKit Agents.

Provides:
- Workflow duration histograms
- Phase success/failure counters
- LLM token usage counters
- Agent workload gauges
- Dapr connectivity status

Metrics are exposed at /metrics endpoint for Prometheus scraping.
"""

from __future__ import annotations

import logging
import os
import time
from contextlib import contextmanager
from typing import Generator, Optional

from prometheus_client import (
    Counter,
    Gauge,
    Histogram,
    Info,
    CollectorRegistry,
    generate_latest,
    CONTENT_TYPE_LATEST,
)

logger = logging.getLogger(__name__)

# Singleton registry
_registry: Optional[CollectorRegistry] = None
_metrics: Optional["MetricsService"] = None


def get_metrics_registry() -> CollectorRegistry:
    """Get or create the metrics registry."""
    global _registry
    if _registry is None:
        _registry = CollectorRegistry()
    return _registry


class MetricsService:
    """Prometheus metrics for SpecKit agents."""

    def __init__(self, registry: CollectorRegistry = None):
        """Initialize metrics with optional custom registry."""
        self.registry = registry or get_metrics_registry()
        self._agent_name = os.getenv("AGENT_NAME", "unknown")

        # Workflow metrics
        self.workflow_total = Counter(
            "speckit_workflow_total",
            "Total workflows processed",
            ["status", "agent"],
            registry=self.registry,
        )

        self.workflow_duration = Histogram(
            "speckit_workflow_duration_seconds",
            "Workflow processing duration",
            ["phase", "agent"],
            buckets=[1, 5, 10, 30, 60, 120, 300, 600, 1800],
            registry=self.registry,
        )

        self.workflow_in_progress = Gauge(
            "speckit_workflow_in_progress",
            "Workflows currently in progress",
            ["phase", "agent"],
            registry=self.registry,
        )

        # Phase metrics
        self.phase_total = Counter(
            "speckit_phase_total",
            "Total phases processed",
            ["phase", "status", "agent"],
            registry=self.registry,
        )

        self.phase_duration = Histogram(
            "speckit_phase_duration_seconds",
            "Phase processing duration",
            ["phase", "agent"],
            buckets=[1, 5, 10, 30, 60, 120, 300],
            registry=self.registry,
        )

        # LLM metrics
        self.llm_requests_total = Counter(
            "speckit_llm_requests_total",
            "Total LLM API requests",
            ["model", "agent", "status"],
            registry=self.registry,
        )

        self.llm_tokens_total = Counter(
            "speckit_llm_tokens_total",
            "Total LLM tokens consumed",
            ["model", "agent", "direction"],
            registry=self.registry,
        )

        self.llm_request_duration = Histogram(
            "speckit_llm_request_duration_seconds",
            "LLM request duration",
            ["model", "agent"],
            buckets=[0.5, 1, 2, 5, 10, 30, 60],
            registry=self.registry,
        )

        # Tool metrics
        self.tool_invocations_total = Counter(
            "speckit_tool_invocations_total",
            "Total tool invocations",
            ["tool", "agent", "status"],
            registry=self.registry,
        )

        self.tool_duration = Histogram(
            "speckit_tool_duration_seconds",
            "Tool invocation duration",
            ["tool", "agent"],
            buckets=[0.1, 0.5, 1, 5, 10, 30],
            registry=self.registry,
        )

        # Agent metrics
        self.agent_workload = Gauge(
            "speckit_agent_workload",
            "Current agent workload",
            ["agent", "instance"],
            registry=self.registry,
        )

        self.agent_status = Gauge(
            "speckit_agent_status",
            "Agent health status (1=healthy, 0=unhealthy)",
            ["agent", "instance"],
            registry=self.registry,
        )

        # Dapr metrics
        self.dapr_pubsub_messages = Counter(
            "speckit_dapr_pubsub_messages_total",
            "Dapr pub/sub messages",
            ["topic", "direction", "agent"],
            registry=self.registry,
        )

        self.dapr_state_operations = Counter(
            "speckit_dapr_state_operations_total",
            "Dapr state store operations",
            ["store", "operation", "status", "agent"],
            registry=self.registry,
        )

        # Error metrics
        self.errors_total = Counter(
            "speckit_errors_total",
            "Total errors",
            ["type", "agent"],
            registry=self.registry,
        )

        # Agent info
        self.agent_info = Info(
            "speckit_agent",
            "Agent information",
            registry=self.registry,
        )
        self.agent_info.info({
            "name": self._agent_name,
            "version": os.getenv("AGENT_VERSION", "unknown"),
        })

    # -------------------------------------------------------------------------
    # Workflow Tracking
    # -------------------------------------------------------------------------

    def record_workflow_started(self, phase: str):
        """Record workflow start."""
        self.workflow_in_progress.labels(phase=phase, agent=self._agent_name).inc()

    def record_workflow_completed(self, phase: str, status: str, duration: float):
        """Record workflow completion."""
        self.workflow_total.labels(status=status, agent=self._agent_name).inc()
        self.workflow_duration.labels(phase=phase, agent=self._agent_name).observe(
            duration
        )
        self.workflow_in_progress.labels(phase=phase, agent=self._agent_name).dec()

    @contextmanager
    def track_workflow(self, phase: str) -> Generator[None, None, None]:
        """Context manager to track workflow duration."""
        self.record_workflow_started(phase)
        start_time = time.time()
        status = "success"
        try:
            yield
        except Exception:
            status = "error"
            raise
        finally:
            duration = time.time() - start_time
            self.record_workflow_completed(phase, status, duration)

    # -------------------------------------------------------------------------
    # Phase Tracking
    # -------------------------------------------------------------------------

    def record_phase_completed(self, phase: str, status: str, duration: float):
        """Record phase completion."""
        self.phase_total.labels(
            phase=phase, status=status, agent=self._agent_name
        ).inc()
        self.phase_duration.labels(phase=phase, agent=self._agent_name).observe(
            duration
        )

    @contextmanager
    def track_phase(self, phase: str) -> Generator[None, None, None]:
        """Context manager to track phase duration."""
        start_time = time.time()
        status = "success"
        try:
            yield
        except Exception:
            status = "error"
            raise
        finally:
            duration = time.time() - start_time
            self.record_phase_completed(phase, status, duration)

    # -------------------------------------------------------------------------
    # LLM Tracking
    # -------------------------------------------------------------------------

    def record_llm_request(
        self,
        model: str,
        status: str,
        duration: float,
        input_tokens: int = 0,
        output_tokens: int = 0,
    ):
        """Record LLM request metrics."""
        self.llm_requests_total.labels(
            model=model, agent=self._agent_name, status=status
        ).inc()

        self.llm_request_duration.labels(
            model=model, agent=self._agent_name
        ).observe(duration)

        if input_tokens > 0:
            self.llm_tokens_total.labels(
                model=model, agent=self._agent_name, direction="input"
            ).inc(input_tokens)

        if output_tokens > 0:
            self.llm_tokens_total.labels(
                model=model, agent=self._agent_name, direction="output"
            ).inc(output_tokens)

    @contextmanager
    def track_llm_request(self, model: str) -> Generator[dict, None, None]:
        """Context manager to track LLM request.

        Usage:
            with metrics.track_llm_request("claude-3-opus") as tracker:
                response = await llm.call(...)
                tracker["input_tokens"] = response.usage.input_tokens
                tracker["output_tokens"] = response.usage.output_tokens
        """
        tracker = {"input_tokens": 0, "output_tokens": 0}
        start_time = time.time()
        status = "success"
        try:
            yield tracker
        except Exception:
            status = "error"
            raise
        finally:
            duration = time.time() - start_time
            self.record_llm_request(
                model=model,
                status=status,
                duration=duration,
                input_tokens=tracker.get("input_tokens", 0),
                output_tokens=tracker.get("output_tokens", 0),
            )

    # -------------------------------------------------------------------------
    # Tool Tracking
    # -------------------------------------------------------------------------

    def record_tool_invocation(self, tool: str, status: str, duration: float):
        """Record tool invocation metrics."""
        self.tool_invocations_total.labels(
            tool=tool, agent=self._agent_name, status=status
        ).inc()
        self.tool_duration.labels(tool=tool, agent=self._agent_name).observe(duration)

    @contextmanager
    def track_tool(self, tool: str) -> Generator[None, None, None]:
        """Context manager to track tool invocation."""
        start_time = time.time()
        status = "success"
        try:
            yield
        except Exception:
            status = "error"
            raise
        finally:
            duration = time.time() - start_time
            self.record_tool_invocation(tool, status, duration)

    # -------------------------------------------------------------------------
    # Agent Status
    # -------------------------------------------------------------------------

    def set_agent_workload(self, instance: str, workload: int):
        """Set current agent workload."""
        self.agent_workload.labels(agent=self._agent_name, instance=instance).set(
            workload
        )

    def set_agent_healthy(self, instance: str, is_healthy: bool):
        """Set agent health status."""
        self.agent_status.labels(agent=self._agent_name, instance=instance).set(
            1 if is_healthy else 0
        )

    # -------------------------------------------------------------------------
    # Dapr Operations
    # -------------------------------------------------------------------------

    def record_pubsub_message(self, topic: str, direction: str):
        """Record pub/sub message.

        Args:
            topic: Topic name
            direction: "published" or "received"
        """
        self.dapr_pubsub_messages.labels(
            topic=topic, direction=direction, agent=self._agent_name
        ).inc()

    def record_state_operation(self, store: str, operation: str, success: bool):
        """Record state store operation.

        Args:
            store: State store name
            operation: "save", "get", "delete"
            success: Whether operation succeeded
        """
        status = "success" if success else "error"
        self.dapr_state_operations.labels(
            store=store, operation=operation, status=status, agent=self._agent_name
        ).inc()

    # -------------------------------------------------------------------------
    # Error Tracking
    # -------------------------------------------------------------------------

    def record_error(self, error_type: str):
        """Record error occurrence."""
        self.errors_total.labels(type=error_type, agent=self._agent_name).inc()

    # -------------------------------------------------------------------------
    # Export
    # -------------------------------------------------------------------------

    def get_metrics(self) -> bytes:
        """Generate metrics output for Prometheus."""
        return generate_latest(self.registry)

    def get_content_type(self) -> str:
        """Get content type for metrics response."""
        return CONTENT_TYPE_LATEST


def get_metrics_service() -> MetricsService:
    """Get or create the metrics service singleton."""
    global _metrics
    if _metrics is None:
        _metrics = MetricsService()
    return _metrics
