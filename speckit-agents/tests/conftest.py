"""Pytest configuration and shared fixtures for SpecKit Agent tests.

Provides:
- Mock Dapr client for state/pubsub operations
- Mock Langfuse client for tracing
- Test workflow and artifact factories
- Environment configuration for isolated testing
"""

from __future__ import annotations

import os
from datetime import datetime
from typing import Any, Optional
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import UUID, uuid4

import pytest

from src.common.models import (
    Artifact,
    ArtifactType,
    Workflow,
    WorkflowPhase,
    WorkflowStatus,
)


# =============================================================================
# Environment Fixtures
# =============================================================================


@pytest.fixture(autouse=True)
def mock_environment(monkeypatch):
    """Set up test environment variables."""
    env_vars = {
        "AGENT_NAME": "test-agent",
        "AGENT_PORT": "8000",
        "TEAM_NAME": "speckit",
        "PUBSUB_NAME": "messagepubsub",
        "WORKFLOW_STATE_STORE": "workflowstatestore",
        "REGISTRY_STATE_STORE": "agentregistrystore",
        "MEMORY_STORE": "memorystore",
        "DAPR_HTTP_PORT": "3500",
        "DAPR_GRPC_PORT": "50001",
        "LANGFUSE_ENABLED": "false",
        "OTEL_ENABLED": "false",
        "ARTIFACTS_PATH": "/tmp/test-artifacts",
    }
    for key, value in env_vars.items():
        monkeypatch.setenv(key, value)


@pytest.fixture
def reset_singletons():
    """Reset singleton instances between tests."""
    # Clear cached settings
    import src.common.config as config_module
    config_module._settings = None

    yield

    # Clean up after test
    config_module._settings = None


# =============================================================================
# Mock Dapr Client
# =============================================================================


class MockDaprState:
    """Mock Dapr state store."""

    def __init__(self):
        self.data: dict[str, bytes] = {}

    def save_state(self, store_name: str, key: str, value: str, **kwargs):
        self.data[f"{store_name}:{key}"] = value.encode() if isinstance(value, str) else value

    def get_state(self, store_name: str, key: str, **kwargs):
        full_key = f"{store_name}:{key}"
        data = self.data.get(full_key)

        class StateResponse:
            def __init__(self, data):
                self.data = data

        return StateResponse(data)

    def delete_state(self, store_name: str, key: str, **kwargs):
        full_key = f"{store_name}:{key}"
        self.data.pop(full_key, None)


class MockDaprPubSub:
    """Mock Dapr pub/sub."""

    def __init__(self):
        self.published: list[dict] = []
        self.topics: dict[str, list[str]] = {}
        self.dead_letter: dict[str, list[str]] = {}

    def publish_event(
        self,
        pubsub_name: str,
        topic_name: str,
        data: str,
        data_content_type: str = "application/json",
        **kwargs,
    ):
        self.published.append({
            "pubsub_name": pubsub_name,
            "topic_name": topic_name,
            "data": data,
            "content_type": data_content_type,
        })
        # Store by topic for retrieval
        if topic_name not in self.topics:
            self.topics[topic_name] = []
        self.topics[topic_name].append(data)

    def get_messages(self, topic_name: str) -> list[str]:
        """Get all messages from a topic."""
        return self.topics.get(topic_name, [])

    def acknowledge(self, topic_name: str):
        """Acknowledge and clear messages from a topic."""
        self.topics[topic_name] = []

    def move_to_dead_letter(self, topic_name: str):
        """Move all messages from topic to dead letter queue."""
        dlq_name = f"{topic_name}-dlq"
        if topic_name in self.topics:
            if dlq_name not in self.dead_letter:
                self.dead_letter[dlq_name] = []
            self.dead_letter[dlq_name].extend(self.topics[topic_name])
            self.topics[topic_name] = []
            # Also make DLQ accessible via get_messages
            self.topics[dlq_name] = self.dead_letter[dlq_name]


class MockDaprClient:
    """Mock Dapr client combining state and pub/sub."""

    def __init__(self):
        self._state = MockDaprState()
        self._pubsub = MockDaprPubSub()

    def save_state(self, *args, **kwargs):
        return self._state.save_state(*args, **kwargs)

    def get_state(self, *args, **kwargs):
        return self._state.get_state(*args, **kwargs)

    def delete_state(self, *args, **kwargs):
        return self._state.delete_state(*args, **kwargs)

    def publish_event(self, *args, **kwargs):
        return self._pubsub.publish_event(*args, **kwargs)

    def close(self):
        pass

    @property
    def published_events(self) -> list[dict]:
        return self._pubsub.published

    @property
    def stored_state(self) -> dict[str, bytes]:
        return self._state.data


@pytest.fixture
def mock_dapr_client():
    """Provide a mock Dapr client."""
    return MockDaprClient()


@pytest.fixture
def patch_dapr_client(mock_dapr_client):
    """Patch DaprClient with mock."""
    with patch("dapr.clients.DaprClient", return_value=mock_dapr_client):
        yield mock_dapr_client


# =============================================================================
# Mock Langfuse
# =============================================================================


class MockLangfuseTrace:
    """Mock Langfuse trace."""

    def __init__(self, trace_id: str = None):
        self.id = trace_id or str(uuid4())
        self.generations: list[dict] = []
        self.spans: list[dict] = []
        self.events: list[dict] = []

    def generation(self, **kwargs) -> "MockLangfuseGeneration":
        gen = MockLangfuseGeneration(**kwargs)
        self.generations.append(kwargs)
        return gen

    def span(self, **kwargs) -> "MockLangfuseSpan":
        span = MockLangfuseSpan(**kwargs)
        self.spans.append(kwargs)
        return span

    def event(self, **kwargs):
        self.events.append(kwargs)


class MockLangfuseGeneration:
    """Mock Langfuse generation."""

    def __init__(self, **kwargs):
        self.kwargs = kwargs
        self.ended = False
        self.output = None
        self.usage = None

    def end(self, output=None, usage=None, **kwargs):
        self.ended = True
        self.output = output
        self.usage = usage


class MockLangfuseSpan:
    """Mock Langfuse span."""

    def __init__(self, **kwargs):
        self.kwargs = kwargs
        self.ended = False
        self.output = None

    def end(self, output=None, **kwargs):
        self.ended = True
        self.output = output


class MockLangfuseClient:
    """Mock Langfuse client."""

    def __init__(self):
        self.traces: list[MockLangfuseTrace] = []
        self.flushed = False

    def trace(self, **kwargs) -> MockLangfuseTrace:
        trace = MockLangfuseTrace()
        self.traces.append(trace)
        return trace

    def flush(self):
        self.flushed = True


@pytest.fixture
def mock_langfuse():
    """Provide a mock Langfuse client."""
    return MockLangfuseClient()


# =============================================================================
# Model Factories
# =============================================================================


@pytest.fixture
def sample_workflow() -> Workflow:
    """Create a sample workflow for testing."""
    return Workflow(
        id=uuid4(),
        feature_description="Implement user authentication with OAuth2",
        status=WorkflowStatus.PENDING,
        current_phase=WorkflowPhase.SPECIFICATION,
        current_agent="orchestrator",
        artifacts=[],
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow(),
    )


@pytest.fixture
def sample_artifact(sample_workflow) -> Artifact:
    """Create a sample artifact for testing."""
    return Artifact(
        workflow_id=sample_workflow.id,
        type=ArtifactType.SPEC,
        path="spec.md",
        content_hash="abc123def456",
        created_by="specifier",
        created_at=datetime.utcnow(),
    )


@pytest.fixture
def workflow_factory():
    """Factory for creating workflows with custom properties."""

    def _create(
        status: WorkflowStatus = WorkflowStatus.PENDING,
        phase: WorkflowPhase = WorkflowPhase.SPECIFICATION,
        feature: str = "Test feature",
    ) -> Workflow:
        return Workflow(
            id=uuid4(),
            feature_description=feature,
            status=status,
            current_phase=phase,
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )

    return _create


# =============================================================================
# Async Utilities
# =============================================================================


@pytest.fixture
def async_mock():
    """Create an async mock that can be awaited."""
    return AsyncMock()


# =============================================================================
# Temporary Directory
# =============================================================================


@pytest.fixture
def temp_artifacts_dir(tmp_path):
    """Provide a temporary artifacts directory."""
    artifacts = tmp_path / "artifacts"
    artifacts.mkdir()
    return artifacts
