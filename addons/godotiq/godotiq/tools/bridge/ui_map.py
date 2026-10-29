"""H01 — godotiq_ui_map: Map all UI elements in the running game.

Returns structured layout of all Control nodes: positions, text,
interactivity, visibility. Identifies small touch targets and
provides complete UI hierarchy for the agent to understand
what's on screen.

Game must be running.
"""

from __future__ import annotations

from godotiq.bridge.session import get_bridge


async def ui_map(
    root: str = "",
    include_invisible: bool = False,
    max_depth: int = 10,
    detail: str = "normal",
    session_id: int | None = None,
    max_output_nodes: int = 200,
    max_visited_nodes: int = 5000,
) -> dict:
    """Map UI elements in the running game.

    Args:
        root: Root node name to start from (e.g. "GameHUD"). Empty = entire UI tree.
        include_invisible: Include hidden elements (default False).
        max_depth: Maximum tree traversal depth (default 10).
        detail: "brief", "normal" (default), or "full".
        max_output_nodes: Maximum UI records returned (hard-capped game-side).
        max_visited_nodes: Maximum scene nodes inspected (hard-capped game-side).

    Returns:
        Dict with root, total_controls, interactive_elements,
        touch_targets_too_small, layout hierarchy.
    """
    params = {
        "root": root,
        "include_invisible": include_invisible,
        "max_depth": max_depth,
        "detail": detail,
        "max_output_nodes": max_output_nodes,
        "max_visited_nodes": max_visited_nodes,
    }
    if session_id is not None:
        params["session_id"] = session_id

    bridge = await get_bridge()
    return await bridge.request("ui_map", params=params, timeout=10.0)
