"""MCP tools for test execution.

Provides tools for running pytest tests with optional coverage,
used by the implementer agent for TDD workflow.
"""

from __future__ import annotations

import asyncio
import logging
import subprocess
from typing import Any

logger = logging.getLogger(__name__)


# ============================================================================
# Tool Functions
# ============================================================================


async def run_tests(
    test_path: str,
    coverage: bool = False,
    verbose: bool = True,
    timeout_seconds: int = 300,
) -> dict[str, Any]:
    """Execute pytest test suite.

    Args:
        test_path: Path to test file or directory
        coverage: Whether to collect coverage data
        verbose: Whether to use verbose output
        timeout_seconds: Maximum execution time (default 5 minutes)

    Returns:
        Dict with test results
    """
    # Build pytest command
    cmd = ["pytest", test_path]

    if verbose:
        cmd.append("-v")

    if coverage:
        cmd.extend(["--cov", "--cov-report=term-missing"])

    # Add short traceback for cleaner output
    cmd.append("--tb=short")

    logger.info(f"Running tests: {' '.join(cmd)}")

    try:
        # Run pytest in subprocess
        result = await asyncio.to_thread(
            subprocess.run,
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
        )

        # Build output message
        output_parts = []

        if result.returncode == 0:
            output_parts.append("Tests PASSED")
        else:
            output_parts.append(f"Tests FAILED (exit code: {result.returncode})")

        if result.stdout:
            output_parts.append("\n--- STDOUT ---")
            output_parts.append(result.stdout)

        if result.stderr:
            output_parts.append("\n--- STDERR ---")
            output_parts.append(result.stderr)

        output = "\n".join(output_parts)

        return {
            "success": result.returncode == 0,
            "exit_code": result.returncode,
            "content": [{"type": "text", "text": output}],
        }

    except subprocess.TimeoutExpired:
        logger.error(f"Test execution timed out after {timeout_seconds}s")
        return {
            "success": False,
            "exit_code": -1,
            "content": [
                {"type": "text", "text": f"Test execution timed out after {timeout_seconds} seconds"}
            ],
        }
    except FileNotFoundError:
        logger.error("pytest not found - ensure it's installed")
        return {
            "success": False,
            "exit_code": -1,
            "content": [{"type": "text", "text": "pytest not found. Install with: pip install pytest"}],
        }
    except Exception as e:
        logger.error(f"Failed to run tests: {e}")
        return {
            "success": False,
            "exit_code": -1,
            "content": [{"type": "text", "text": f"Error running tests: {str(e)}"}],
        }


async def run_specific_test(
    test_path: str,
    test_name: str,
    timeout_seconds: int = 60,
) -> dict[str, Any]:
    """Execute a specific test by name.

    Args:
        test_path: Path to test file
        test_name: Name of the test function (e.g., "test_create_user")
        timeout_seconds: Maximum execution time

    Returns:
        Dict with test results
    """
    # Build pytest command with -k to select specific test
    cmd = ["pytest", test_path, "-k", test_name, "-v", "--tb=short"]

    logger.info(f"Running specific test: {test_name} in {test_path}")

    try:
        result = await asyncio.to_thread(
            subprocess.run,
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
        )

        output_parts = []
        if result.returncode == 0:
            output_parts.append(f"Test '{test_name}' PASSED")
        else:
            output_parts.append(f"Test '{test_name}' FAILED (exit code: {result.returncode})")

        if result.stdout:
            output_parts.append("\n--- STDOUT ---")
            output_parts.append(result.stdout)

        if result.stderr:
            output_parts.append("\n--- STDERR ---")
            output_parts.append(result.stderr)

        return {
            "success": result.returncode == 0,
            "exit_code": result.returncode,
            "content": [{"type": "text", "text": "\n".join(output_parts)}],
        }

    except subprocess.TimeoutExpired:
        return {
            "success": False,
            "exit_code": -1,
            "content": [{"type": "text", "text": f"Test timed out after {timeout_seconds} seconds"}],
        }
    except Exception as e:
        return {
            "success": False,
            "exit_code": -1,
            "content": [{"type": "text", "text": f"Error: {str(e)}"}],
        }


async def check_test_file(test_path: str) -> dict[str, Any]:
    """Check if test file exists and list available tests.

    Args:
        test_path: Path to test file

    Returns:
        Dict with test file info
    """
    # Use pytest --collect-only to list tests
    cmd = ["pytest", test_path, "--collect-only", "-q"]

    try:
        result = await asyncio.to_thread(
            subprocess.run,
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
        )

        if result.returncode == 0 and result.stdout:
            return {
                "success": True,
                "content": [
                    {
                        "type": "text",
                        "text": f"Tests found in {test_path}:\n{result.stdout}",
                    }
                ],
            }
        else:
            error_msg = result.stderr if result.stderr else "No tests found or file not accessible"
            return {
                "success": False,
                "content": [{"type": "text", "text": error_msg}],
            }

    except Exception as e:
        return {
            "success": False,
            "content": [{"type": "text", "text": f"Error: {str(e)}"}],
        }


# ============================================================================
# MCP Server Factory
# ============================================================================

TEST_TOOLS = {
    "run_tests": {
        "description": "Execute pytest test suite",
        "parameters": {
            "test_path": {"type": "string", "description": "Path to test file or directory"},
            "coverage": {
                "type": "boolean",
                "description": "Whether to collect coverage data",
                "default": False,
            },
            "verbose": {
                "type": "boolean",
                "description": "Whether to use verbose output",
                "default": True,
            },
            "timeout_seconds": {
                "type": "integer",
                "description": "Maximum execution time in seconds",
                "default": 300,
            },
        },
        "function": run_tests,
    },
    "run_specific_test": {
        "description": "Execute a specific test by name",
        "parameters": {
            "test_path": {"type": "string", "description": "Path to test file"},
            "test_name": {"type": "string", "description": "Name of the test function"},
            "timeout_seconds": {
                "type": "integer",
                "description": "Maximum execution time",
                "default": 60,
            },
        },
        "function": run_specific_test,
    },
    "check_test_file": {
        "description": "Check test file and list available tests",
        "parameters": {
            "test_path": {"type": "string", "description": "Path to test file"},
        },
        "function": check_test_file,
    },
}


def create_tests_mcp_server():
    """Create MCP server for test tools.

    Returns:
        MCP server instance with test tools registered.
    """
    return {
        "name": "tests",
        "version": "1.0.0",
        "tools": TEST_TOOLS,
    }


tests_mcp_server = create_tests_mcp_server()
