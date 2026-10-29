"""Shared bridge connection manager — singleton with async lock."""

from __future__ import annotations

import asyncio
import os
from pathlib import Path
from typing import Optional

from godotiq.bridge.connection import BridgeConnection, BridgeConnectionError
from godotiq.config import GodotIQConfig, load_config
from godotiq.session import discover_project_root

_bridge: Optional[BridgeConnection] = None
_bridge_lock: Optional[asyncio.Lock] = None
_configured_project_root: Path | None = None
_configured_config: GodotIQConfig | None = None
_bridge_settings_key: tuple[str | None, int, str] | None = None
_last_bridge_error: str | None = None

DEFAULT_PORT = 6107
TOKEN_DIRNAME = ".godotiq"
TOKEN_FILENAME = "bridge_token"


def configure_bridge(project_root: str | Path | None, config: GodotIQConfig | None = None) -> None:
    """Store the active project root/config for later bridge connections."""
    global _configured_project_root, _configured_config

    if project_root is None:
        _configured_project_root = None
    else:
        _configured_project_root = Path(project_root).resolve()
    _configured_config = config


def _get_project_root() -> Path | None:
    """Resolve the project root for bridge settings."""
    if _configured_project_root is not None:
        return _configured_project_root
    return discover_project_root()


def _get_config(project_root: Path | None) -> GodotIQConfig:
    """Resolve the active GodotIQ config."""
    if _configured_config is not None:
        return _configured_config
    if project_root is None:
        return GodotIQConfig()
    return load_config(str(project_root / ".godotiq.json"))


def _resolve_port(project_root: Path | None) -> int:
    """Resolve bridge port with env override, then config, then default."""
    env_port = os.environ.get("GODOTIQ_ADDON_PORT")
    if env_port:
        try:
            return int(env_port)
        except (ValueError, TypeError):
            return DEFAULT_PORT

    config = _get_config(project_root)
    server_cfg = config.server if isinstance(config.server, dict) else {}
    port = server_cfg.get("addon_port")
    if isinstance(port, (int, float)):
        return int(port)
    return DEFAULT_PORT


def _load_token(project_root: Path | None) -> str:
    """Load the addon-owned bridge token.

    The editor addon is the single writer. Keeping token creation on one side
    avoids a first-start race where Python and GDScript persist different
    tokens at the same path.
    """
    if project_root is None:
        return ""

    token_dir = project_root / TOKEN_DIRNAME
    token_path = token_dir / TOKEN_FILENAME

    if token_path.exists():
        try:
            existing = token_path.read_text(encoding="utf-8").strip()
        except OSError:
            existing = ""
        if existing:
            return existing

    return ""


def get_last_bridge_error() -> str | None:
    """Return the last bridge setup/connection error message, if any."""
    return _last_bridge_error


def _current_settings() -> tuple[Path | None, int, str]:
    """Resolve the current bridge settings."""
    project_root = _get_project_root()
    return project_root, _resolve_port(project_root), _load_token(project_root)


def _normalize_local_path(value: str | Path) -> str:
    """Normalize a local project path for identity comparison."""
    return os.path.normcase(os.path.realpath(os.fspath(value))).rstrip("\\/")


async def get_bridge() -> BridgeConnection:
    """Return a connected bridge instance, creating one if needed.

    Lazily initializes the async lock and auto-reconnects if the
    previous connection was lost.
    """
    global _bridge, _bridge_lock, _last_bridge_error
    global _bridge_settings_key

    if _bridge_lock is None:
        _bridge_lock = asyncio.Lock()

    async with _bridge_lock:
        project_root, port, token = _current_settings()
        if not token:
            _last_bridge_error = (
                "Bridge token unavailable. Start the Godot editor with the addon enabled "
                f"so it can create {TOKEN_DIRNAME}/{TOKEN_FILENAME}."
            )
            raise BridgeConnectionError(_last_bridge_error)
        settings_key = (str(project_root) if project_root is not None else None, port, token)

        if (
            _bridge is not None
            and _bridge.is_connected
            and _bridge_settings_key == settings_key
        ):
            return _bridge

        if _bridge is not None:
            await _bridge.disconnect()

        _bridge = BridgeConnection(port=port, token=token)
        try:
            await _bridge.connect()
            context = await _bridge.request("editor_context", timeout=5.0)
            addon_project_path = context.get("project_path")
            if project_root is None or not addon_project_path:
                raise BridgeConnectionError("Addon did not provide a project identity")
            if _normalize_local_path(addon_project_path) != _normalize_local_path(project_root):
                raise BridgeConnectionError(
                    "Connected addon belongs to a different project: "
                    f"{addon_project_path} (expected {project_root})"
                )
        except Exception:
            await _bridge.disconnect()
            _bridge = None
            raise
        _bridge_settings_key = settings_key
        _last_bridge_error = None
        return _bridge


async def get_bridge_or_none() -> Optional[BridgeConnection]:
    """Return a connected bridge or None on failure.

    Used by editor_context for graceful fallback when the addon
    is not running.
    """
    global _last_bridge_error
    try:
        return await get_bridge()
    except Exception as exc:
        _last_bridge_error = str(exc)
        return None


async def close_bridge() -> None:
    """Disconnect and discard the shared bridge instance.

    Called in the server lifespan's finally block.
    """
    global _bridge, _bridge_lock, _bridge_settings_key, _last_bridge_error

    if _bridge_lock is None:
        _bridge_lock = asyncio.Lock()

    async with _bridge_lock:
        if _bridge is not None:
            try:
                await _bridge.disconnect()
            except Exception:
                pass
            _bridge = None
        _bridge_settings_key = None
        _last_bridge_error = None
