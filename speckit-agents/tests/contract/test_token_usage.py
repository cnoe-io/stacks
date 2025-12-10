"""Contract tests for token usage schema.

Tests:
- TokenUsage model validation
- Token counting accuracy
- Usage aggregation across phases
- Model-specific token tracking

These tests validate the contract for token usage reporting in Langfuse.
"""

from datetime import datetime
from uuid import uuid4

import pytest
from pydantic import ValidationError

from src.common.models import TokenUsage


class TestTokenUsageSchema:
    """Contract tests for TokenUsage model."""

    def test_token_usage_required_fields(self):
        """TokenUsage should require all token counts."""
        with pytest.raises(ValidationError):
            TokenUsage()

        with pytest.raises(ValidationError):
            TokenUsage(prompt_tokens=100)

        with pytest.raises(ValidationError):
            TokenUsage(prompt_tokens=100, completion_tokens=50)

    def test_token_usage_with_valid_fields(self):
        """TokenUsage should accept valid token counts."""
        usage = TokenUsage(
            prompt_tokens=100,
            completion_tokens=50,
            total_tokens=150,
        )

        assert usage.prompt_tokens == 100
        assert usage.completion_tokens == 50
        assert usage.total_tokens == 150

    def test_token_usage_rejects_negative_values(self):
        """TokenUsage should reject negative token counts."""
        with pytest.raises(ValidationError):
            TokenUsage(
                prompt_tokens=-1,
                completion_tokens=50,
                total_tokens=49,
            )

        with pytest.raises(ValidationError):
            TokenUsage(
                prompt_tokens=100,
                completion_tokens=-50,
                total_tokens=50,
            )

    def test_token_usage_allows_zero_values(self):
        """TokenUsage should allow zero token counts."""
        usage = TokenUsage(
            prompt_tokens=0,
            completion_tokens=0,
            total_tokens=0,
        )

        assert usage.prompt_tokens == 0
        assert usage.completion_tokens == 0
        assert usage.total_tokens == 0


class TestTokenUsageConsistency:
    """Tests for token usage value consistency."""

    def test_total_equals_sum_of_parts(self):
        """Total tokens should equal prompt + completion."""
        # Note: This is a contract test - we verify the model accepts
        # values where total = prompt + completion
        prompt = 100
        completion = 50
        total = prompt + completion

        usage = TokenUsage(
            prompt_tokens=prompt,
            completion_tokens=completion,
            total_tokens=total,
        )

        assert usage.total_tokens == usage.prompt_tokens + usage.completion_tokens

    def test_inconsistent_total_is_accepted(self):
        """Model accepts inconsistent totals (validation is external)."""
        # The model itself doesn't validate consistency
        # This tests the contract that values are stored as provided
        usage = TokenUsage(
            prompt_tokens=100,
            completion_tokens=50,
            total_tokens=200,  # Incorrect total
        )

        # Values stored as provided
        assert usage.total_tokens == 200
        # Consumer should validate consistency if needed
        assert usage.total_tokens != usage.prompt_tokens + usage.completion_tokens


class TestTokenUsageAggregation:
    """Tests for aggregating token usage across operations."""

    def test_aggregate_multiple_usages(self):
        """Should be able to aggregate multiple TokenUsage instances."""
        usages = [
            TokenUsage(prompt_tokens=100, completion_tokens=50, total_tokens=150),
            TokenUsage(prompt_tokens=200, completion_tokens=100, total_tokens=300),
            TokenUsage(prompt_tokens=150, completion_tokens=75, total_tokens=225),
        ]

        total_prompt = sum(u.prompt_tokens for u in usages)
        total_completion = sum(u.completion_tokens for u in usages)
        total_all = sum(u.total_tokens for u in usages)

        assert total_prompt == 450
        assert total_completion == 225
        assert total_all == 675

    def test_phase_wise_aggregation(self):
        """Should support aggregating by workflow phase."""
        phase_usages = {
            "specification": [
                TokenUsage(prompt_tokens=500, completion_tokens=200, total_tokens=700),
            ],
            "planning": [
                TokenUsage(prompt_tokens=800, completion_tokens=400, total_tokens=1200),
                TokenUsage(prompt_tokens=600, completion_tokens=300, total_tokens=900),
            ],
            "task_generation": [
                TokenUsage(prompt_tokens=300, completion_tokens=150, total_tokens=450),
            ],
            "implementation": [
                TokenUsage(prompt_tokens=2000, completion_tokens=1000, total_tokens=3000),
                TokenUsage(prompt_tokens=1500, completion_tokens=750, total_tokens=2250),
                TokenUsage(prompt_tokens=1000, completion_tokens=500, total_tokens=1500),
            ],
        }

        phase_totals = {}
        for phase, usages in phase_usages.items():
            phase_totals[phase] = sum(u.total_tokens for u in usages)

        assert phase_totals["specification"] == 700
        assert phase_totals["planning"] == 2100
        assert phase_totals["task_generation"] == 450
        assert phase_totals["implementation"] == 6750


class TestTokenUsageForLangfuse:
    """Tests for token usage format expected by Langfuse."""

    def test_langfuse_compatible_format(self):
        """TokenUsage should be serializable for Langfuse."""
        usage = TokenUsage(
            prompt_tokens=1000,
            completion_tokens=500,
            total_tokens=1500,
        )

        # Langfuse expects these exact field names
        data = usage.model_dump()

        assert "prompt_tokens" in data
        assert "completion_tokens" in data
        assert "total_tokens" in data

    def test_langfuse_alternative_field_names(self):
        """Verify Langfuse-compatible field mapping."""
        usage = TokenUsage(
            prompt_tokens=1000,
            completion_tokens=500,
            total_tokens=1500,
        )

        # Langfuse SDK also accepts 'input' and 'output' format
        langfuse_format = {
            "input": usage.prompt_tokens,
            "output": usage.completion_tokens,
            "total": usage.total_tokens,
        }

        assert langfuse_format["input"] == 1000
        assert langfuse_format["output"] == 500
        assert langfuse_format["total"] == 1500


class TestModelSpecificUsage:
    """Tests for model-specific token usage tracking."""

    def test_track_usage_by_model(self):
        """Should support tracking usage by model name."""
        model_usages = {
            "claude-3-opus-20240229": [
                TokenUsage(prompt_tokens=1000, completion_tokens=500, total_tokens=1500),
            ],
            "claude-3-sonnet-20240229": [
                TokenUsage(prompt_tokens=800, completion_tokens=400, total_tokens=1200),
            ],
            "claude-3-haiku-20240307": [
                TokenUsage(prompt_tokens=600, completion_tokens=300, total_tokens=900),
            ],
        }

        for model, usages in model_usages.items():
            assert len(usages) > 0
            assert all(isinstance(u, TokenUsage) for u in usages)

    def test_aggregate_by_model(self):
        """Should aggregate usage per model."""
        model_usages = {
            "claude-3-opus-20240229": TokenUsage(
                prompt_tokens=5000, completion_tokens=2500, total_tokens=7500
            ),
            "claude-3-sonnet-20240229": TokenUsage(
                prompt_tokens=3000, completion_tokens=1500, total_tokens=4500
            ),
        }

        total_all_models = sum(u.total_tokens for u in model_usages.values())
        assert total_all_models == 12000


class TestTokenUsageEdgeCases:
    """Tests for edge cases in token usage."""

    def test_large_token_counts(self):
        """Should handle large token counts."""
        usage = TokenUsage(
            prompt_tokens=100000,
            completion_tokens=50000,
            total_tokens=150000,
        )

        assert usage.prompt_tokens == 100000
        assert usage.completion_tokens == 50000

    def test_small_token_counts(self):
        """Should handle small token counts."""
        usage = TokenUsage(
            prompt_tokens=1,
            completion_tokens=1,
            total_tokens=2,
        )

        assert usage.prompt_tokens == 1
        assert usage.completion_tokens == 1

    def test_json_serialization(self):
        """TokenUsage should serialize to JSON correctly."""
        usage = TokenUsage(
            prompt_tokens=100,
            completion_tokens=50,
            total_tokens=150,
        )

        json_str = usage.model_dump_json()
        assert '"prompt_tokens":100' in json_str or '"prompt_tokens": 100' in json_str

        # Round-trip
        restored = TokenUsage.model_validate_json(json_str)
        assert restored.prompt_tokens == usage.prompt_tokens
        assert restored.completion_tokens == usage.completion_tokens
        assert restored.total_tokens == usage.total_tokens


class TestTokenUsageMetrics:
    """Tests for token usage metrics calculation."""

    def test_calculate_cost_estimate(self):
        """Should support cost estimation from token usage."""
        usage = TokenUsage(
            prompt_tokens=1000,
            completion_tokens=500,
            total_tokens=1500,
        )

        # Example: Claude 3 Opus pricing (per 1M tokens)
        input_price_per_million = 15.0
        output_price_per_million = 75.0

        input_cost = (usage.prompt_tokens / 1_000_000) * input_price_per_million
        output_cost = (usage.completion_tokens / 1_000_000) * output_price_per_million
        total_cost = input_cost + output_cost

        assert input_cost == 0.015
        assert output_cost == 0.0375
        assert total_cost == 0.0525

    def test_calculate_tokens_per_phase(self):
        """Should calculate average tokens per phase."""
        phase_counts = {
            "specification": 1,
            "planning": 3,
            "task_generation": 1,
            "implementation": 5,
        }

        phase_tokens = {
            "specification": 700,
            "planning": 2100,
            "task_generation": 450,
            "implementation": 6750,
        }

        avg_tokens = {}
        for phase in phase_counts:
            avg_tokens[phase] = phase_tokens[phase] / phase_counts[phase]

        assert avg_tokens["specification"] == 700
        assert avg_tokens["planning"] == 700
        assert avg_tokens["task_generation"] == 450
        assert avg_tokens["implementation"] == 1350
