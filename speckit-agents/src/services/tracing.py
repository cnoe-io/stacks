"""OpenTelemetry tracing service for Jaeger integration.

Provides distributed tracing across SpecKit agents using:
- OpenTelemetry SDK for trace/span creation
- Jaeger exporter for trace collection
- W3C Trace Context propagation via Dapr pub/sub metadata
- Correlation with Langfuse traces via custom attributes

Tracing flow:
1. Orchestrator creates root span for workflow
2. Each agent creates child span linked via W3C traceparent
3. Spans include workflow_id, agent_name, langfuse_trace_id
4. Jaeger correlates with Langfuse via shared trace identifiers
"""

from __future__ import annotations

import logging
import os
from contextvars import ContextVar
from dataclasses import dataclass
from typing import Any, Optional

from opentelemetry import trace
from opentelemetry.context import Context
from opentelemetry.propagate import extract, inject
from opentelemetry.sdk.resources import Resource, SERVICE_NAME
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.trace import Span, SpanKind, Status, StatusCode
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

logger = logging.getLogger(__name__)

# Context variable for current trace context
_current_context: ContextVar[Optional[Context]] = ContextVar("trace_context", default=None)


@dataclass
class TracingConfig:
    """Configuration for OpenTelemetry tracing."""

    enabled: bool = True
    service_name: str = "speckit-agents"
    jaeger_endpoint: str = ""
    jaeger_agent_host: str = "localhost"
    jaeger_agent_port: int = 6831

    @classmethod
    def from_env(cls) -> "TracingConfig":
        """Load tracing configuration from environment."""
        return cls(
            enabled=os.getenv("OTEL_ENABLED", "true").lower() == "true",
            service_name=os.getenv("OTEL_SERVICE_NAME", "speckit-agents"),
            jaeger_endpoint=os.getenv("OTEL_EXPORTER_JAEGER_ENDPOINT", ""),
            jaeger_agent_host=os.getenv(
                "OTEL_EXPORTER_JAEGER_AGENT_HOST", "localhost"
            ),
            jaeger_agent_port=int(os.getenv("OTEL_EXPORTER_JAEGER_AGENT_PORT", "6831")),
        )


class TracingService:
    """Distributed tracing service using OpenTelemetry and Jaeger.

    Provides:
    - Trace/span creation with agent and workflow context
    - W3C Trace Context propagation for cross-agent tracing
    - Langfuse correlation via custom span attributes
    - Graceful degradation when Jaeger is unavailable
    """

    def __init__(self, config: Optional[TracingConfig] = None) -> None:
        """Initialize tracing service.

        Args:
            config: Optional tracing configuration
        """
        self.config = config or TracingConfig.from_env()
        self._tracer: Optional[trace.Tracer] = None
        self._provider: Optional[TracerProvider] = None
        self._initialized = False
        self._propagator = TraceContextTextMapPropagator()

    def initialize(self) -> None:
        """Initialize OpenTelemetry tracing with Jaeger exporter."""
        if self._initialized:
            return

        if not self.config.enabled:
            logger.info("OpenTelemetry tracing disabled")
            self._initialized = True
            return

        try:
            # Create resource with service name
            resource = Resource.create({SERVICE_NAME: self.config.service_name})

            # Create tracer provider
            self._provider = TracerProvider(resource=resource)

            # Configure Jaeger exporter
            if self.config.jaeger_endpoint:
                # Use HTTP/Thrift exporter for collector
                from opentelemetry.exporter.jaeger.thrift import JaegerExporter

                exporter = JaegerExporter(
                    collector_endpoint=self.config.jaeger_endpoint,
                )
            else:
                # Use UDP agent exporter
                from opentelemetry.exporter.jaeger.thrift import JaegerExporter

                exporter = JaegerExporter(
                    agent_host_name=self.config.jaeger_agent_host,
                    agent_port=self.config.jaeger_agent_port,
                )

            # Add batch span processor
            span_processor = BatchSpanProcessor(exporter)
            self._provider.add_span_processor(span_processor)

            # Set as global tracer provider
            trace.set_tracer_provider(self._provider)

            # Get tracer
            self._tracer = trace.get_tracer(
                instrumenting_module_name="speckit-agents",
                instrumenting_library_version="2.0.0",
            )

            self._initialized = True
            logger.info(
                f"OpenTelemetry initialized: service={self.config.service_name}"
            )

        except Exception as e:
            logger.warning(f"Failed to initialize OpenTelemetry: {e}")
            self._initialized = True  # Don't retry

    @property
    def tracer(self) -> Optional[trace.Tracer]:
        """Get the OpenTelemetry tracer."""
        if not self._initialized:
            self.initialize()
        return self._tracer

    def start_span(
        self,
        name: str,
        kind: SpanKind = SpanKind.INTERNAL,
        attributes: Optional[dict[str, Any]] = None,
        parent_context: Optional[Context] = None,
    ) -> Optional[Span]:
        """Start a new trace span.

        Args:
            name: Span name (e.g., "specifier.process_task")
            kind: Span kind (internal, server, client, producer, consumer)
            attributes: Initial span attributes
            parent_context: Optional parent context for linking

        Returns:
            Span object or None if tracing disabled
        """
        if not self.tracer:
            return None

        # Use provided context or current context
        context = parent_context or _current_context.get()

        try:
            span = self.tracer.start_span(
                name=name,
                kind=kind,
                attributes=attributes or {},
                context=context,
            )
            return span
        except Exception as e:
            logger.warning(f"Failed to start span: {e}")
            return None

    def start_workflow_span(
        self,
        workflow_id: str,
        agent_name: str,
        operation: str,
        langfuse_trace_id: Optional[str] = None,
    ) -> Optional[Span]:
        """Start a span for workflow processing.

        Args:
            workflow_id: Workflow UUID
            agent_name: Agent processing the workflow
            operation: Operation name (e.g., "process_task")
            langfuse_trace_id: Optional Langfuse trace ID for correlation

        Returns:
            Span with workflow attributes set
        """
        attributes = {
            "speckit.workflow_id": workflow_id,
            "speckit.agent_name": agent_name,
            "speckit.operation": operation,
        }

        if langfuse_trace_id:
            attributes["speckit.langfuse_trace_id"] = langfuse_trace_id

        return self.start_span(
            name=f"{agent_name}.{operation}",
            kind=SpanKind.INTERNAL,
            attributes=attributes,
        )

    def set_span_attributes(
        self,
        span: Optional[Span],
        attributes: dict[str, Any],
    ) -> None:
        """Set attributes on a span.

        Args:
            span: Span to update
            attributes: Key-value attributes
        """
        if span is None:
            return

        try:
            for key, value in attributes.items():
                if value is not None:
                    span.set_attribute(key, str(value))
        except Exception as e:
            logger.warning(f"Failed to set span attributes: {e}")

    def record_exception(
        self,
        span: Optional[Span],
        exception: Exception,
        attributes: Optional[dict[str, Any]] = None,
    ) -> None:
        """Record an exception on a span.

        Args:
            span: Span to record exception on
            exception: Exception to record
            attributes: Additional attributes
        """
        if span is None:
            return

        try:
            span.record_exception(exception, attributes=attributes)
            span.set_status(Status(StatusCode.ERROR, str(exception)))
        except Exception as e:
            logger.warning(f"Failed to record exception: {e}")

    def end_span(
        self,
        span: Optional[Span],
        success: bool = True,
        error: Optional[str] = None,
    ) -> None:
        """End a span with status.

        Args:
            span: Span to end
            success: Whether operation succeeded
            error: Optional error message
        """
        if span is None:
            return

        try:
            if success:
                span.set_status(Status(StatusCode.OK))
            else:
                span.set_status(Status(StatusCode.ERROR, error or "Unknown error"))
            span.end()
        except Exception as e:
            logger.warning(f"Failed to end span: {e}")

    def shutdown(self) -> None:
        """Shutdown the tracing service."""
        if self._provider:
            try:
                self._provider.shutdown()
            except Exception as e:
                logger.warning(f"Error shutting down tracer: {e}")


# Singleton instance
_tracing_service: Optional[TracingService] = None


def get_tracing_service() -> TracingService:
    """Get or create the singleton tracing service."""
    global _tracing_service
    if _tracing_service is None:
        _tracing_service = TracingService()
        _tracing_service.initialize()
    return _tracing_service


def inject_trace_context(carrier: dict[str, str]) -> dict[str, str]:
    """Inject W3C trace context into carrier for propagation.

    Args:
        carrier: Dictionary to inject headers into

    Returns:
        Carrier with traceparent and optional tracestate headers
    """
    try:
        inject(carrier)
    except Exception as e:
        logger.warning(f"Failed to inject trace context: {e}")
    return carrier


def extract_trace_context(carrier: dict[str, str]) -> Optional[Context]:
    """Extract W3C trace context from carrier.

    Args:
        carrier: Dictionary with traceparent/tracestate headers

    Returns:
        OpenTelemetry context or None
    """
    try:
        context = extract(carrier)
        _current_context.set(context)
        return context
    except Exception as e:
        logger.warning(f"Failed to extract trace context: {e}")
        return None
