"""Langfuse Client Service for LLM observability.

Provides:
- Session management for workflow tracking
- Trace and generation recording
- Incomplete generation detection
- Token usage and cost estimation
- Cross-system trace correlation
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from typing import Any, Optional
from uuid import UUID

logger = logging.getLogger(__name__)


class GenerationStatus(str, Enum):
    """Status of an LLM generation."""

    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    INCOMPLETE = "incomplete"
    FAILED = "failed"


@dataclass
class GenerationInfo:
    """Information about an LLM generation."""

    id: str
    name: str
    model: str
    status: GenerationStatus
    input_tokens: int = 0
    output_tokens: int = 0
    total_tokens: int = 0
    latency_ms: Optional[float] = None
    error: Optional[str] = None
    started_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None
    completion_reason: Optional[str] = None


@dataclass
class IncompleteGenerationInfo:
    """Information about incomplete LLM generations for recovery."""

    generation_id: str
    workflow_id: str
    agent_name: str
    phase: str
    reason: str
    partial_output: Optional[str] = None
    input_tokens_consumed: int = 0
    timestamp: Optional[datetime] = None


class LangfuseClient:
    """Client for interacting with Langfuse observability platform."""

    def __init__(
        self,
        public_key: Optional[str] = None,
        secret_key: Optional[str] = None,
        host: Optional[str] = None,
    ):
        """Initialize Langfuse client.

        Args:
            public_key: Langfuse public key
            secret_key: Langfuse secret key
            host: Langfuse host URL
        """
        self.public_key = public_key or os.getenv("LANGFUSE_PUBLIC_KEY")
        self.secret_key = secret_key or os.getenv("LANGFUSE_SECRET_KEY")
        self.host = host or os.getenv("LANGFUSE_HOST", "https://cloud.langfuse.com")

        self._client = None
        self._initialized = False

        # Track active generations for incomplete detection
        self._active_generations: dict[str, GenerationInfo] = {}

    @property
    def is_configured(self) -> bool:
        """Check if Langfuse is properly configured."""
        return bool(self.public_key and self.secret_key)

    def _ensure_client(self):
        """Lazily initialize Langfuse client."""
        if self._initialized:
            return

        if not self.is_configured:
            logger.warning("Langfuse not configured, observability disabled")
            self._initialized = True
            return

        try:
            from langfuse import Langfuse

            self._client = Langfuse(
                public_key=self.public_key,
                secret_key=self.secret_key,
                host=self.host,
            )
            self._initialized = True
            logger.info(f"Langfuse client initialized: {self.host}")
        except ImportError:
            logger.warning("Langfuse package not installed")
            self._initialized = True
        except Exception as e:
            logger.error(f"Failed to initialize Langfuse client: {e}")
            self._initialized = True

    # =========================================================================
    # Session Management
    # =========================================================================

    def create_session(
        self,
        workflow_id: UUID,
        metadata: Optional[dict[str, Any]] = None,
    ) -> Optional[str]:
        """Create a new Langfuse session for a workflow.

        Args:
            workflow_id: Workflow ID
            metadata: Optional session metadata

        Returns:
            Session ID or None if not configured
        """
        self._ensure_client()
        if not self._client:
            return None

        session_id = f"workflow-{workflow_id}"
        logger.debug(f"Created Langfuse session: {session_id}")
        return session_id

    def create_trace(
        self,
        workflow_id: UUID,
        name: str,
        metadata: Optional[dict[str, Any]] = None,
    ) -> Optional[str]:
        """Create a new trace for a workflow operation.

        Args:
            workflow_id: Workflow ID
            name: Trace name
            metadata: Optional trace metadata

        Returns:
            Trace ID or None if not configured
        """
        self._ensure_client()
        if not self._client:
            return None

        try:
            trace = self._client.trace(
                name=name,
                session_id=f"workflow-{workflow_id}",
                metadata=metadata or {},
            )
            logger.debug(f"Created Langfuse trace: {trace.id}")
            return trace.id
        except Exception as e:
            logger.error(f"Failed to create trace: {e}")
            return None

    # =========================================================================
    # Generation Tracking
    # =========================================================================

    def start_generation(
        self,
        trace_id: str,
        name: str,
        model: str,
        input_messages: list[dict[str, Any]],
        workflow_id: Optional[UUID] = None,
        agent_name: Optional[str] = None,
    ) -> Optional[str]:
        """Start tracking a new LLM generation.

        Args:
            trace_id: Parent trace ID
            name: Generation name
            model: Model name
            input_messages: Input messages to LLM
            workflow_id: Optional workflow ID
            agent_name: Optional agent name

        Returns:
            Generation ID or None if not configured
        """
        self._ensure_client()
        if not self._client:
            return None

        try:
            trace = self._client.trace(id=trace_id)
            generation = trace.generation(
                name=name,
                model=model,
                input=input_messages,
                metadata={
                    "workflow_id": str(workflow_id) if workflow_id else None,
                    "agent_name": agent_name,
                    "status": GenerationStatus.IN_PROGRESS.value,
                },
            )

            # Track active generation for incomplete detection
            gen_info = GenerationInfo(
                id=generation.id,
                name=name,
                model=model,
                status=GenerationStatus.IN_PROGRESS,
                started_at=datetime.utcnow(),
            )
            self._active_generations[generation.id] = gen_info

            logger.debug(f"Started generation: {generation.id}")
            return generation.id
        except Exception as e:
            logger.error(f"Failed to start generation: {e}")
            return None

    def complete_generation(
        self,
        generation_id: str,
        output: str,
        input_tokens: int = 0,
        output_tokens: int = 0,
        completion_reason: str = "stop",
    ) -> None:
        """Mark a generation as completed.

        Args:
            generation_id: Generation ID
            output: Generated output
            input_tokens: Number of input tokens
            output_tokens: Number of output tokens
            completion_reason: Reason for completion (stop, length, etc.)
        """
        self._ensure_client()
        if not self._client:
            return

        # Update tracking
        if generation_id in self._active_generations:
            gen_info = self._active_generations[generation_id]
            gen_info.status = GenerationStatus.COMPLETED
            gen_info.input_tokens = input_tokens
            gen_info.output_tokens = output_tokens
            gen_info.total_tokens = input_tokens + output_tokens
            gen_info.ended_at = datetime.utcnow()
            gen_info.completion_reason = completion_reason

            if gen_info.started_at:
                gen_info.latency_ms = (
                    gen_info.ended_at - gen_info.started_at
                ).total_seconds() * 1000

            # Remove from active tracking (completed normally)
            del self._active_generations[generation_id]

        try:
            # Note: In actual implementation, would call generation.end()
            logger.debug(
                f"Completed generation: {generation_id}, "
                f"tokens: {input_tokens}+{output_tokens}={input_tokens + output_tokens}"
            )
        except Exception as e:
            logger.error(f"Failed to complete generation: {e}")

    def fail_generation(
        self,
        generation_id: str,
        error: str,
        partial_output: Optional[str] = None,
    ) -> None:
        """Mark a generation as failed.

        Args:
            generation_id: Generation ID
            error: Error message
            partial_output: Any partial output before failure
        """
        self._ensure_client()
        if not self._client:
            return

        # Update tracking
        if generation_id in self._active_generations:
            gen_info = self._active_generations[generation_id]
            gen_info.status = GenerationStatus.FAILED
            gen_info.error = error
            gen_info.ended_at = datetime.utcnow()

            if gen_info.started_at:
                gen_info.latency_ms = (
                    gen_info.ended_at - gen_info.started_at
                ).total_seconds() * 1000

        try:
            logger.warning(f"Failed generation: {generation_id}, error: {error}")
        except Exception as e:
            logger.error(f"Failed to record generation failure: {e}")

    # =========================================================================
    # Incomplete Generation Detection
    # =========================================================================

    def detect_incomplete_generations(
        self,
        workflow_id: Optional[UUID] = None,
    ) -> list[IncompleteGenerationInfo]:
        """Detect incomplete or stalled generations.

        Args:
            workflow_id: Optional workflow ID to filter by

        Returns:
            List of incomplete generation information
        """
        incomplete = []

        for gen_id, gen_info in list(self._active_generations.items()):
            if gen_info.status == GenerationStatus.IN_PROGRESS:
                # Check if generation has been running too long (> 5 minutes)
                if gen_info.started_at:
                    elapsed = (datetime.utcnow() - gen_info.started_at).total_seconds()
                    if elapsed > 300:  # 5 minutes
                        # Mark as incomplete
                        gen_info.status = GenerationStatus.INCOMPLETE

                        incomplete.append(
                            IncompleteGenerationInfo(
                                generation_id=gen_id,
                                workflow_id=str(workflow_id) if workflow_id else "",
                                agent_name=gen_info.name,
                                phase="",
                                reason="timeout",
                                timestamp=gen_info.started_at,
                            )
                        )

        return incomplete

    def get_incomplete_generations_for_workflow(
        self,
        workflow_id: UUID,
    ) -> list[IncompleteGenerationInfo]:
        """Get incomplete generations for a specific workflow.

        Args:
            workflow_id: Workflow ID

        Returns:
            List of incomplete generations
        """
        return self.detect_incomplete_generations(workflow_id)

    def mark_generation_incomplete(
        self,
        generation_id: str,
        reason: str,
        partial_output: Optional[str] = None,
        input_tokens_consumed: int = 0,
    ) -> IncompleteGenerationInfo:
        """Manually mark a generation as incomplete.

        Args:
            generation_id: Generation ID
            reason: Reason for incompleteness
            partial_output: Any partial output
            input_tokens_consumed: Tokens consumed before interruption

        Returns:
            Incomplete generation info
        """
        if generation_id in self._active_generations:
            gen_info = self._active_generations[generation_id]
            gen_info.status = GenerationStatus.INCOMPLETE
            gen_info.input_tokens = input_tokens_consumed

        info = IncompleteGenerationInfo(
            generation_id=generation_id,
            workflow_id="",
            agent_name="",
            phase="",
            reason=reason,
            partial_output=partial_output,
            input_tokens_consumed=input_tokens_consumed,
            timestamp=datetime.utcnow(),
        )

        logger.warning(f"Marked generation incomplete: {generation_id}, reason: {reason}")
        return info

    def can_resume_generation(self, generation_id: str) -> bool:
        """Check if a generation can be resumed.

        Args:
            generation_id: Generation ID

        Returns:
            True if generation can be resumed
        """
        if generation_id not in self._active_generations:
            return False

        gen_info = self._active_generations[generation_id]
        return gen_info.status in [
            GenerationStatus.INCOMPLETE,
            GenerationStatus.IN_PROGRESS,
        ]

    # =========================================================================
    # Token Usage and Cost Estimation
    # =========================================================================

    def get_token_usage_summary(
        self,
        workflow_id: Optional[UUID] = None,
    ) -> dict[str, Any]:
        """Get token usage summary.

        Args:
            workflow_id: Optional workflow ID to filter

        Returns:
            Token usage summary
        """
        total_input = 0
        total_output = 0
        by_model: dict[str, dict[str, int]] = {}

        for gen_info in self._active_generations.values():
            total_input += gen_info.input_tokens
            total_output += gen_info.output_tokens

            if gen_info.model not in by_model:
                by_model[gen_info.model] = {"input": 0, "output": 0}

            by_model[gen_info.model]["input"] += gen_info.input_tokens
            by_model[gen_info.model]["output"] += gen_info.output_tokens

        return {
            "total_input_tokens": total_input,
            "total_output_tokens": total_output,
            "total_tokens": total_input + total_output,
            "by_model": by_model,
        }

    # =========================================================================
    # Cleanup
    # =========================================================================

    def flush(self) -> None:
        """Flush any pending data to Langfuse."""
        self._ensure_client()
        if self._client:
            try:
                self._client.flush()
                logger.debug("Flushed Langfuse client")
            except Exception as e:
                logger.error(f"Failed to flush Langfuse: {e}")

    def shutdown(self) -> None:
        """Shutdown the client gracefully."""
        # Mark any active generations as incomplete before shutdown
        for gen_id in list(self._active_generations.keys()):
            self.mark_generation_incomplete(gen_id, "shutdown")

        self.flush()
        if self._client:
            try:
                self._client.shutdown()
            except Exception:
                pass


# Singleton instance
_langfuse_client: Optional[LangfuseClient] = None


def get_langfuse_client() -> LangfuseClient:
    """Get or create the Langfuse client singleton."""
    global _langfuse_client
    if _langfuse_client is None:
        _langfuse_client = LangfuseClient()
    return _langfuse_client
