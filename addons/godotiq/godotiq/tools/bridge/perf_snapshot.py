"""Performance snapshot tool — capture runtime metrics from the Godot game."""

from __future__ import annotations

from godotiq.bridge.session import get_bridge


async def perf_snapshot(detail: str = "normal", session_id: int | None = None) -> dict:
    """Capture a performance snapshot from the running Godot game.

    Args:
        detail: "brief" (fps + draw_calls only), "normal" (default), or "full".

    Returns:
        Dict with fps, draw_calls, triangles, objects, texture_mem, buffer_mem,
        video_mem, total_nodes, orphan_nodes.
    """
    bridge = await get_bridge()
    params = {"session_id": session_id} if session_id is not None else {}
    result = await bridge.request("perf_snapshot", params=params)

    detail = (detail or "normal").lower()
    if detail == "brief":
        return {
            "fps": result.get("fps"),
            "draw_calls": result.get("draw_calls"),
        }

    return result
