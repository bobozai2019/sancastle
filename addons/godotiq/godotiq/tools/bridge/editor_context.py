"""Editor context tool — get live editor state or filesystem fallback."""

from __future__ import annotations

from godotiq.bridge.connection import BridgeConnectionError, BridgeError, BridgeTimeoutError
from godotiq.bridge.session import get_bridge_or_none, get_last_bridge_error


async def editor_context(project_path: str = "") -> dict:
    """Get the current editor state from the Godot addon.

    Returns connected editor state (open scenes, selected nodes, game state,
    project path) when the addon is running, or a filesystem-based fallback
    when disconnected.

    Returns:
        Dict with editor context and addon_connected flag.
    """
    bridge = await get_bridge_or_none()
    bridge_error: str | None = None

    if bridge is not None:
        try:
            result = await bridge.request("editor_context")
        except (BridgeConnectionError, BridgeTimeoutError, BridgeError) as exc:
            bridge_error = str(exc)
        else:
            result["addon_connected"] = True
            return result

    if bridge_error is None:
        bridge_error = get_last_bridge_error()

    fallback = {
        "addon_connected": False,
        "project_path": project_path,
        "note": "GodotIQ addon not connected. Editor state unavailable. "
                "Enable the addon in Godot to get live editor context.",
    }
    if bridge_error:
        fallback["bridge_error"] = bridge_error
    return fallback
