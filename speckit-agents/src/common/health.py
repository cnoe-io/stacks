"""Health and readiness endpoints for SpecKit agents."""

from __future__ import annotations

import logging
from datetime import datetime
from typing import TYPE_CHECKING

import httpx
from fastapi import APIRouter, Response

from .config import get_config
from .models import HealthResponse, ReadinessResponse

if TYPE_CHECKING:
    pass

logger = logging.getLogger(__name__)

router = APIRouter(tags=["Health"])


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
