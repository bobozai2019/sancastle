"""Shared runtime helpers for MCP tool wrappers."""

from __future__ import annotations

from functools import wraps
from pathlib import Path
from typing import Any, Awaitable, Callable, ParamSpec, TypeVar

from godotiq.config import GodotIQConfig, load_config
from godotiq.session import GodotIQSession, discover_project_root

P = ParamSpec("P")
R = TypeVar("R")


def get_session_from_ctx(ctx: Any) -> GodotIQSession | None:
    """Return the loaded session from a FastMCP Context-like object."""
    if ctx is None:
        return None

    request_context = getattr(ctx, "request_context", None)
    lifespan_context = getattr(request_context, "lifespan_context", None)
    if not isinstance(lifespan_context, dict):
        return None

    session = lifespan_context.get("session")
    if isinstance(session, GodotIQSession):
        return session
    return None


def get_project_root(ctx: Any = None) -> Path | None:
    """Resolve the active Godot project root from session or discovery."""
    session = get_session_from_ctx(ctx)
    if session is not None:
        return session.project_root.resolve()
    return discover_project_root()


def get_config(ctx: Any = None) -> GodotIQConfig:
    """Resolve the active project config from session or filesystem."""
    session = get_session_from_ctx(ctx)
    if session is not None:
        return session.config

    project_root = get_project_root(ctx)
    if project_root is None:
        return GodotIQConfig()
    return load_config(str(project_root / ".godotiq.json"))


def refresh_session(ctx: Any = None) -> None:
    """Refresh the loaded session after a successful disk mutation."""
    session = get_session_from_ctx(ctx)
    if session is not None:
        session.refresh()


def ensure_tool_enabled(tool_name: str, ctx: Any = None) -> dict | None:
    """Return a structured error when a tool is disabled by project config."""
    if tool_name == "godotiq_ping":
        return None

    config = get_config(ctx)
    if not config.is_tool_disabled(tool_name):
        return None

    return {
        "status": "DISABLED",
        "error": f"Tool disabled by project config: {tool_name}",
        "tool": tool_name,
    }


def configure_bridge_from_ctx(ctx: Any = None) -> None:
    """Push project root/config into the shared bridge session manager."""
    from godotiq.bridge.session import configure_bridge

    project_root = get_project_root(ctx)
    configure_bridge(project_root, get_config(ctx))


def guard_tool(
    tool_name: str,
    *,
    configure_bridge: bool = False,
) -> Callable[[Callable[P, Awaitable[R]]], Callable[P, Awaitable[R | dict]]]:
    """Decorator that enforces disabled_tools and optional bridge setup."""

    def decorator(func: Callable[P, Awaitable[R]]) -> Callable[P, Awaitable[R | dict]]:
        @wraps(func)
        async def wrapper(*args: P.args, **kwargs: P.kwargs) -> R | dict:
            ctx = kwargs.get("ctx")
            disabled = ensure_tool_enabled(tool_name, ctx)
            if disabled is not None:
                return disabled
            if configure_bridge:
                configure_bridge_from_ctx(ctx)
            return await func(*args, **kwargs)

        return wrapper

    return decorator
