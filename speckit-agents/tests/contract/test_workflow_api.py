"""Contract tests for workflow API endpoints.

Tests:
- POST /run request/response schema validation
- GET /workflows/{id}/status response schema validation
- Error response format validation
"""

from datetime import datetime
from uuid import UUID, uuid4

import pytest
from pydantic import ValidationError

from src.common.models import (
    ErrorResponse,
    WorkflowRequest,
    WorkflowResponse,
    WorkflowStatus,
    WorkflowStatusResponse,
    WorkflowPhase,
)


class TestWorkflowRequestContract:
    """Contract tests for POST /run request schema."""

    def test_valid_request_minimal(self):
        """Request with minimum required fields should be valid."""
        request = WorkflowRequest(
            task="Implement a user authentication system with OAuth2 support"
        )
        assert request.task is not None
        assert len(request.task) >= 10

    def test_valid_request_long_description(self):
        """Request with long task description should be valid."""
        long_task = "A" * 5000
        request = WorkflowRequest(task=long_task)
        assert len(request.task) == 5000

    def test_invalid_request_empty_task(self):
        """Empty task should fail validation."""
        with pytest.raises(ValidationError) as exc_info:
            WorkflowRequest(task="")
        errors = exc_info.value.errors()
        assert any("min_length" in str(e) or "too_short" in str(e) for e in errors)

    def test_invalid_request_short_task(self):
        """Task shorter than 10 characters should fail validation."""
        with pytest.raises(ValidationError):
            WorkflowRequest(task="short")

    def test_invalid_request_too_long_task(self):
        """Task exceeding 10000 characters should fail validation."""
        with pytest.raises(ValidationError):
            WorkflowRequest(task="A" * 10001)

    def test_request_serialization(self):
        """Request should serialize to JSON correctly."""
        request = WorkflowRequest(
            task="Add a REST API endpoint for user management"
        )
        json_data = request.model_dump_json()
        assert "task" in json_data
        assert "user management" in json_data


class TestWorkflowResponseContract:
    """Contract tests for POST /run response schema."""

    def test_valid_response_pending(self):
        """Response with pending status should be valid."""
        instance_id = uuid4()
        response = WorkflowResponse(
            instance_id=instance_id,
            status=WorkflowStatus.PENDING,
            status_url=f"/status/{instance_id}",
        )
        assert response.instance_id == instance_id
        assert response.status == WorkflowStatus.PENDING
        assert str(instance_id) in response.status_url

    def test_valid_response_specifying(self):
        """Response with specifying status should be valid."""
        response = WorkflowResponse(
            instance_id=uuid4(),
            status=WorkflowStatus.SPECIFYING,
        )
        assert response.status == WorkflowStatus.SPECIFYING
        assert response.status_url is None

    def test_response_serialization(self):
        """Response should serialize to JSON correctly."""
        instance_id = uuid4()
        response = WorkflowResponse(
            instance_id=instance_id,
            status=WorkflowStatus.SPECIFYING,
            status_url=f"/workflows/{instance_id}/status",
        )
        json_data = response.model_dump_json()
        assert str(instance_id) in json_data
        assert "specifying" in json_data


class TestWorkflowStatusResponseContract:
    """Contract tests for GET /workflows/{id}/status response schema."""

    def test_valid_status_response_pending(self):
        """Status response for pending workflow should be valid."""
        workflow_id = uuid4()
        now = datetime.utcnow()

        response = WorkflowStatusResponse(
            id=workflow_id,
            status=WorkflowStatus.PENDING,
            current_phase=WorkflowPhase.SPECIFICATION,
            progress_percent=0,
            artifacts=[],
            created_at=now,
            updated_at=now,
        )

        assert response.id == workflow_id
        assert response.status == WorkflowStatus.PENDING
        assert response.current_phase == WorkflowPhase.SPECIFICATION
        assert response.progress_percent == 0
        assert response.artifacts == []
        assert response.error is None

    def test_valid_status_response_in_progress(self):
        """Status response for in-progress workflow should be valid."""
        workflow_id = uuid4()
        now = datetime.utcnow()

        response = WorkflowStatusResponse(
            id=workflow_id,
            status=WorkflowStatus.PLANNING,
            current_phase=WorkflowPhase.PLANNING,
            current_agent="planner",
            progress_percent=35,
            artifacts=[],
            created_at=now,
            updated_at=now,
        )

        assert response.status == WorkflowStatus.PLANNING
        assert response.current_agent == "planner"
        assert response.progress_percent == 35

    def test_valid_status_response_completed(self):
        """Status response for completed workflow should be valid."""
        workflow_id = uuid4()
        now = datetime.utcnow()

        response = WorkflowStatusResponse(
            id=workflow_id,
            status=WorkflowStatus.COMPLETED,
            current_phase=WorkflowPhase.IMPLEMENTATION,
            progress_percent=100,
            artifacts=[],
            created_at=now,
            updated_at=now,
        )

        assert response.status == WorkflowStatus.COMPLETED
        assert response.progress_percent == 100

    def test_valid_status_response_failed(self):
        """Status response for failed workflow should include error."""
        workflow_id = uuid4()
        now = datetime.utcnow()

        response = WorkflowStatusResponse(
            id=workflow_id,
            status=WorkflowStatus.FAILED,
            current_phase=WorkflowPhase.PLANNING,
            progress_percent=30,
            artifacts=[],
            created_at=now,
            updated_at=now,
            error="Claude SDK timeout after 5 minutes",
        )

        assert response.status == WorkflowStatus.FAILED
        assert response.error is not None
        assert "timeout" in response.error

    def test_status_response_serialization(self):
        """Status response should serialize to JSON correctly."""
        workflow_id = uuid4()
        now = datetime.utcnow()

        response = WorkflowStatusResponse(
            id=workflow_id,
            status=WorkflowStatus.SPECIFYING,
            current_phase=WorkflowPhase.SPECIFICATION,
            current_agent="specifier",
            progress_percent=15,
            artifacts=[],
            created_at=now,
            updated_at=now,
        )

        json_data = response.model_dump_json()
        assert str(workflow_id) in json_data
        assert "specifying" in json_data
        assert "specifier" in json_data


class TestErrorResponseContract:
    """Contract tests for error response schema."""

    def test_valid_error_response_simple(self):
        """Simple error response should be valid."""
        response = ErrorResponse(
            error="validation_error",
            message="Invalid task description",
        )

        assert response.error == "validation_error"
        assert response.message == "Invalid task description"
        assert response.details is None

    def test_valid_error_response_with_details(self):
        """Error response with details should be valid."""
        response = ErrorResponse(
            error="workflow_failed",
            message="Workflow execution failed",
            details={
                "phase": "planning",
                "agent": "planner",
                "reason": "API rate limit exceeded",
            },
        )

        assert response.error == "workflow_failed"
        assert response.details is not None
        assert response.details["phase"] == "planning"

    def test_error_response_serialization(self):
        """Error response should serialize to JSON correctly."""
        response = ErrorResponse(
            error="not_found",
            message="Workflow not found",
            details={"workflow_id": str(uuid4())},
        )

        json_data = response.model_dump_json()
        assert "not_found" in json_data
        assert "Workflow not found" in json_data
