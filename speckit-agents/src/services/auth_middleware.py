"""API Authentication Middleware for SpecKit Agents.

Provides:
- API key authentication for external requests
- Service-to-service authentication via Dapr App ID
- Rate limiting per API key
- Request logging with authentication context

Note: For internal Dapr-to-Dapr communication, authentication is handled
by Dapr's mTLS and access control policies.
"""

from __future__ import annotations

import hashlib
import logging
import os
import secrets
import time
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from typing import Callable, Optional

from fastapi import HTTPException, Request, Response
from fastapi.security import APIKeyHeader
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.status import (
    HTTP_401_UNAUTHORIZED,
    HTTP_403_FORBIDDEN,
    HTTP_429_TOO_MANY_REQUESTS,
)

logger = logging.getLogger(__name__)


class AuthScope(str, Enum):
    """API key permission scopes."""

    READ = "read"  # Read workflow status
    WRITE = "write"  # Create workflows
    ADMIN = "admin"  # Full access


@dataclass
class APIKeyInfo:
    """API key metadata."""

    key_hash: str  # SHA-256 hash of the API key
    name: str  # Descriptive name
    scopes: list[AuthScope]
    created_at: datetime = field(default_factory=datetime.utcnow)
    expires_at: Optional[datetime] = None
    rate_limit: int = 100  # Requests per minute
    enabled: bool = True
    metadata: dict = field(default_factory=dict)

    @property
    def is_expired(self) -> bool:
        """Check if key has expired."""
        if self.expires_at is None:
            return False
        return datetime.utcnow() > self.expires_at

    @property
    def is_valid(self) -> bool:
        """Check if key is valid and enabled."""
        return self.enabled and not self.is_expired


@dataclass
class RateLimitState:
    """Rate limit tracking per key."""

    requests: list[float] = field(default_factory=list)  # Timestamps
    window_seconds: int = 60

    def add_request(self) -> int:
        """Add request and return current count in window."""
        now = time.time()
        cutoff = now - self.window_seconds
        self.requests = [t for t in self.requests if t > cutoff]
        self.requests.append(now)
        return len(self.requests)

    def is_rate_limited(self, limit: int) -> bool:
        """Check if current request count exceeds limit."""
        now = time.time()
        cutoff = now - self.window_seconds
        current = sum(1 for t in self.requests if t > cutoff)
        return current >= limit


class AuthConfig:
    """Authentication configuration."""

    def __init__(self):
        self.enabled = os.getenv("AUTH_ENABLED", "false").lower() == "true"
        self.bypass_paths = [
            "/healthz",
            "/ready",
            "/status",
            "/docs",
            "/openapi.json",
            "/redoc",
        ]
        self.internal_header = "dapr-app-id"  # Dapr service identity
        self.api_key_header = "X-API-Key"
        self.trusted_dapr_apps = self._load_trusted_apps()

    def _load_trusted_apps(self) -> set[str]:
        """Load trusted Dapr app IDs from environment."""
        apps = os.getenv("TRUSTED_DAPR_APPS", "")
        return set(app.strip() for app in apps.split(",") if app.strip())


class APIKeyStore:
    """In-memory API key store.

    In production, this would be backed by Dapr state store
    or external secrets manager.
    """

    def __init__(self):
        self._keys: dict[str, APIKeyInfo] = {}
        self._rate_limits: dict[str, RateLimitState] = defaultdict(RateLimitState)
        self._load_default_keys()

    def _load_default_keys(self):
        """Load API keys from environment."""
        # Development key (only in dev mode)
        dev_key = os.getenv("DEV_API_KEY")
        if dev_key:
            self.add_key(
                key=dev_key,
                name="Development Key",
                scopes=[AuthScope.READ, AuthScope.WRITE, AuthScope.ADMIN],
            )

        # Service keys from environment
        service_key = os.getenv("SERVICE_API_KEY")
        if service_key:
            self.add_key(
                key=service_key,
                name="Service Key",
                scopes=[AuthScope.READ, AuthScope.WRITE],
                rate_limit=1000,
            )

    @staticmethod
    def hash_key(key: str) -> str:
        """Hash API key for storage."""
        return hashlib.sha256(key.encode()).hexdigest()

    def add_key(
        self,
        key: str,
        name: str,
        scopes: list[AuthScope],
        rate_limit: int = 100,
        expires_at: Optional[datetime] = None,
    ) -> APIKeyInfo:
        """Add a new API key."""
        key_hash = self.hash_key(key)
        info = APIKeyInfo(
            key_hash=key_hash,
            name=name,
            scopes=scopes,
            rate_limit=rate_limit,
            expires_at=expires_at,
        )
        self._keys[key_hash] = info
        return info

    def validate_key(self, key: str) -> Optional[APIKeyInfo]:
        """Validate API key and return info if valid."""
        key_hash = self.hash_key(key)
        info = self._keys.get(key_hash)

        if info is None:
            return None

        if not info.is_valid:
            return None

        return info

    def check_rate_limit(self, key_hash: str, limit: int) -> tuple[bool, int]:
        """Check rate limit for key.

        Returns:
            Tuple of (is_allowed, current_count)
        """
        state = self._rate_limits[key_hash]
        count = state.add_request()
        is_allowed = count <= limit
        return is_allowed, count

    def generate_key(self) -> str:
        """Generate a new random API key."""
        return secrets.token_urlsafe(32)


class AuthMiddleware(BaseHTTPMiddleware):
    """FastAPI middleware for API authentication."""

    def __init__(self, app, config: AuthConfig = None, key_store: APIKeyStore = None):
        super().__init__(app)
        self.config = config or AuthConfig()
        self.key_store = key_store or APIKeyStore()

    async def dispatch(
        self, request: Request, call_next: Callable
    ) -> Response:
        """Process request through authentication."""
        # Check if auth is enabled
        if not self.config.enabled:
            return await call_next(request)

        # Skip auth for bypass paths
        path = request.url.path.rstrip("/")
        if any(path.startswith(bp) for bp in self.config.bypass_paths):
            return await call_next(request)

        # Check Dapr internal auth (service-to-service)
        dapr_app_id = request.headers.get(self.config.internal_header)
        if dapr_app_id and dapr_app_id in self.config.trusted_dapr_apps:
            request.state.auth_type = "dapr"
            request.state.auth_identity = dapr_app_id
            logger.debug(f"Authenticated via Dapr: {dapr_app_id}")
            return await call_next(request)

        # Check API key
        api_key = request.headers.get(self.config.api_key_header)
        if not api_key:
            logger.warning(f"Missing API key for {request.url.path}")
            raise HTTPException(
                status_code=HTTP_401_UNAUTHORIZED,
                detail="Missing API key",
                headers={"WWW-Authenticate": "ApiKey"},
            )

        # Validate API key
        key_info = self.key_store.validate_key(api_key)
        if key_info is None:
            logger.warning(f"Invalid API key for {request.url.path}")
            raise HTTPException(
                status_code=HTTP_401_UNAUTHORIZED,
                detail="Invalid API key",
            )

        # Check rate limit
        is_allowed, count = self.key_store.check_rate_limit(
            key_info.key_hash, key_info.rate_limit
        )
        if not is_allowed:
            logger.warning(f"Rate limit exceeded for {key_info.name}: {count}")
            raise HTTPException(
                status_code=HTTP_429_TOO_MANY_REQUESTS,
                detail="Rate limit exceeded",
                headers={
                    "X-RateLimit-Limit": str(key_info.rate_limit),
                    "X-RateLimit-Remaining": "0",
                    "Retry-After": "60",
                },
            )

        # Store auth context for handlers
        request.state.auth_type = "api_key"
        request.state.auth_identity = key_info.name
        request.state.auth_scopes = key_info.scopes
        request.state.rate_limit_remaining = key_info.rate_limit - count

        # Add rate limit headers to response
        response = await call_next(request)
        response.headers["X-RateLimit-Limit"] = str(key_info.rate_limit)
        response.headers["X-RateLimit-Remaining"] = str(
            max(0, key_info.rate_limit - count)
        )

        return response


def require_scope(required_scope: AuthScope):
    """Dependency to require specific scope.

    Usage:
        @app.post("/run", dependencies=[Depends(require_scope(AuthScope.WRITE))])
        async def create_workflow(...):
            ...
    """

    async def check_scope(request: Request):
        if not hasattr(request.state, "auth_scopes"):
            # Auth middleware not enabled or bypassed
            return

        scopes = request.state.auth_scopes
        if AuthScope.ADMIN in scopes:
            return  # Admin has all permissions

        if required_scope not in scopes:
            raise HTTPException(
                status_code=HTTP_403_FORBIDDEN,
                detail=f"Insufficient permissions. Required scope: {required_scope.value}",
            )

    return check_scope


# FastAPI dependency for API key header
api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)
