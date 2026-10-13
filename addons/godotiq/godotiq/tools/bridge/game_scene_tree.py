"""godotiq_game_scene_tree: Query the running game's actual scene tree.

Unlike godotiq_scene_tree (which reads the editor's scene tree and returns
stale data after scene transitions), this queries the running game's live
scene tree via the debugger bridge.
"""

from __future__ import annotations

from godotiq.bridge.session import get_bridge

TOOL_NAME = "godotiq_game_scene_tree"
TOOL_DESCRIPTION = (
    "Query the running game's actual scene tree. Unlike godotiq_scene_tree "
    "(editor-side, stale after transitions), this returns live runtime data. "
    "Game must be running."
)


async def game_scene_tree(
    root: str = "",
    depth: int = 3,
    filter_type: str = "",
    session_id: int | None = None,
    max_output_nodes: int = 200,
    max_visited_nodes: int = 5000,
) -> dict:
    """Query the running game's scene tree.

    Args:
        root: Node path to start from (e.g. "/root/Main"). Empty = /root.
        depth: Max tree depth (default 3).
        filter_type: Only include nodes of this type (e.g. "Button").
        max_output_nodes: Maximum node records returned (hard-capped game-side).
        max_visited_nodes: Maximum scene nodes inspected (hard-capped game-side).

    Returns:
        Dict with root, node_count, and nodes list.
    """
    bridge = await get_bridge()
    params = {
        "depth": depth,
        "max_output_nodes": max_output_nodes,
        "max_visited_nodes": max_visited_nodes,
    }
    if root:
        params["root"] = root
    if filter_type:
        params["filter_type"] = filter_type
    if session_id is not None:
        params["session_id"] = session_id
    return await bridge.request("game_scene_tree", params=params, timeout=10.0)
