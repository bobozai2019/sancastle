"""Editor undo/redo action history."""

from __future__ import annotations

from ...bridge.session import get_bridge


async def undo_history() -> dict:
    """Get undo/redo state and GodotIQ action history.

    Returns:
        Dict with can_undo, can_redo, current_action, godotiq_actions list.
    """
    bridge = await get_bridge()
    return await bridge.request("undo_history", timeout=3.0)
