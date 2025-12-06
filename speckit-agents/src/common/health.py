"""Health and readiness endpoints for SpecKit agents.

Provides:
- /healthz: Liveness probe (process alive)
- /ready: Readiness probe (Dapr, Langfuse, Jaeger connectivity)
- /status: Detailed component status for debugging
"""

from __future__ import annotations

import logging
import os
from datetime import datetime
from typing import Any, Optional

import httpx
from fastapi import APIRouter, Response
from pydantic import BaseModel, Field

from .config import get_config
from .models import HealthResponse, ReadinessResponse

logger = logging.getLogger(__name__)

router = APIRouter(tags=["Health"])


class ComponentStatus(BaseModel):
    """Status of an individual component."""

    name: str
    connected: bool
    latency_ms: Optional[float] = None
    error: Optional[str] = None


class DetailedStatusResponse(BaseModel):
    """Detailed status response with all component health."""

    agent: str
    healthy: bool
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    dapr: ComponentStatus
    langfuse: ComponentStatus
    jaeger: ComponentStatus
    components: list[str] = Field(default_factory=list)


@router.get("/healthz", response_model=HealthResponse)
async def liveness() -> HealthResponse:
    """Liveness probe - returns 200 if process is alive."""
    config = get_config()
    return HealthResponse(
        status="healthy",
        agent=config.agent_name,
        timestamp=datetime.utcnow(),
    )


@router.get("/ready", response_model=ReadinessResponse)
async def readiness(response: Response) -> ReadinessResponse:
    """Readiness probe - returns 200 if Dapr sidecar is connected."""
    config = get_config()
    dapr_connected = False
    components_ready: list[str] = []

    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            # Check Dapr sidecar metadata endpoint
            resp = await client.get(config.dapr_metadata_url)
            if resp.status_code == 200:
                dapr_connected = True
                metadata = resp.json()

                # Extract component names from metadata
                components = metadata.get("components", [])
                for component in components:
                    component_name = component.get("name", "")
                    if component_name:
                        components_ready.append(component_name)

                logger.debug(f"Dapr connected, components: {components_ready}")

    except httpx.RequestError as e:
        logger.warning(f"Dapr sidecar not ready: {e}")
    except Exception as e:
        logger.error(f"Error checking Dapr readiness: {e}")

    ready = dapr_connected

    if not ready:
        response.status_code = 503

    return ReadinessResponse(
        ready=ready,
        agent=config.agent_name,
        dapr_connected=dapr_connected,
        components_ready=components_ready,
    )


@router.get("/status", response_model=DetailedStatusResponse)
async def detailed_status() -> DetailedStatusResponse:
    """Detailed status endpoint for debugging component connectivity.

    Checks:
    - Dapr sidecar connectivity and components
    - Langfuse API connectivity (if configured)
    - Jaeger collector connectivity (if configured)
    """
    config = get_config()

    # Check Dapr
    dapr_status = await _check_dapr_status(config)

    # Check Langfuse
    langfuse_status = await _check_langfuse_status(config)

    # Check Jaeger
    jaeger_status = await _check_jaeger_status()

    # Overall health
    healthy = dapr_status.connected

    return DetailedStatusResponse(
        agent=config.agent_name,
        healthy=healthy,
        dapr=dapr_status,
        langfuse=langfuse_status,
        jaeger=jaeger_status,
        components=dapr_status.error.split(",") if not dapr_status.connected else [],
    )


async def _check_dapr_status(config: Any) -> ComponentStatus:
    """Check Dapr sidecar connectivity."""
    import time

    start = time.time()
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(config.dapr_metadata_url)
            latency = (time.time() - start) * 1000

            if resp.status_code == 200:
                metadata = resp.json()
                components = [c.get("name", "") for c in metadata.get("components", [])]
                return ComponentStatus(
                    name="dapr",
                    connected=True,
                    latency_ms=round(latency, 2),
                    error=None,
                )
            else:
                return ComponentStatus(
                    name="dapr",
                    connected=False,
                    latency_ms=round(latency, 2),
                    error=f"HTTP {resp.status_code}",
                )
    except httpx.RequestError as e:
        return ComponentStatus(
            name="dapr",
            connected=False,
            error=str(e),
        )
    except Exception as e:
        return ComponentStatus(
            name="dapr",
            connected=False,
            error=str(e),
        )


async def _check_langfuse_status(config: Any) -> ComponentStatus:
    """Check Langfuse API connectivity."""
    import time

    if not config.langfuse_enabled:
        return ComponentStatus(
            name="langfuse",
            connected=False,
            error="Disabled by configuration",
        )

    if not config.langfuse_host:
        return ComponentStatus(
            name="langfuse",
            connected=False,
            error="Host not configured",
        )

    start = time.time()
    try:
        # Check Langfuse health endpoint
        health_url = f"{config.langfuse_host}/api/public/health"
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(health_url)
            latency = (time.time() - start) * 1000

            if resp.status_code == 200:
                return ComponentStatus(
                    name="langfuse",
                    connected=True,
                    latency_ms=round(latency, 2),
                )
            else:
                return ComponentStatus(
                    name="langfuse",
                    connected=False,
                    latency_ms=round(latency, 2),
                    error=f"HTTP {resp.status_code}",
                )
    except httpx.RequestError as e:
        return ComponentStatus(
            name="langfuse",
            connected=False,
            error=str(e),
        )
    except Exception as e:
        return ComponentStatus(
            name="langfuse",
            connected=False,
            error=str(e),
        )


async def _check_jaeger_status() -> ComponentStatus:
    """Check Jaeger collector connectivity."""
    import time

    jaeger_endpoint = os.getenv("OTEL_EXPORTER_JAEGER_ENDPOINT", "")
    otel_enabled = os.getenv("OTEL_ENABLED", "true").lower() == "true"

    if not otel_enabled:
        return ComponentStatus(
            name="jaeger",
            connected=False,
            error="OpenTelemetry disabled",
        )

    if not jaeger_endpoint:
        # Try agent endpoint
        agent_host = os.getenv("OTEL_EXPORTER_JAEGER_AGENT_HOST", "")
        if not agent_host:
            return ComponentStatus(
                name="jaeger",
                connected=False,
                error="No Jaeger endpoint configured",
            )
        # Can't easily check UDP agent, assume configured
        return ComponentStatus(
            name="jaeger",
            connected=True,
            error="Agent mode (UDP) - connectivity not verified",
        )

    start = time.time()
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            # Jaeger collector doesn't have a health endpoint on /api/traces
            # Just check if endpoint is reachable
            resp = await client.options(jaeger_endpoint)
            latency = (time.time() - start) * 1000

            # Any response is good (collector may return 405 for OPTIONS)
            return ComponentStatus(
                name="jaeger",
                connected=True,
                latency_ms=round(latency, 2),
            )
    except httpx.RequestError as e:
        return ComponentStatus(
            name="jaeger",
            connected=False,
            error=str(e),
        )
    except Exception as e:
        return ComponentStatus(
            name="jaeger",
            connected=False,
            error=str(e),
        )


async def check_dapr_component(component_name: str) -> bool:
    """Check if a specific Dapr component is available."""
    config = get_config()
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(config.dapr_metadata_url)
            if resp.status_code == 200:
                metadata = resp.json()
                components = metadata.get("components", [])
                for component in components:
                    if component.get("name") == component_name:
                        return True
    except Exception as e:
        logger.error(f"Error checking component {component_name}: {e}")
    return False


@router.get("/metrics")
async def metrics() -> Response:
    """Prometheus metrics endpoint for scraping.

    Exposes:
    - Workflow and phase duration histograms
    - LLM token usage counters
    - Tool invocation counters
    - Agent workload gauges
    - Dapr operation counters
    """
    from src.services.metrics import get_metrics_service

    metrics_service = get_metrics_service()
    return Response(
        content=metrics_service.get_metrics(),
        media_type=metrics_service.get_content_type(),
    )
