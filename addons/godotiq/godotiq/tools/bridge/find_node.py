"""godotiq_find_node: Find a single node by name in the running game.

Unlike godotiq_game_scene_tree (which traverses the entire tree and may
be truncated), this searches for one node by name and returns its info.
Much faster and avoids output truncation issues.
"""

from __future__ import annotations

from godotiq.bridge.session import get_bridge

TOOL_NAME = "godotiq_find_node"
TOOL_DESCRIPTION = (
    "Find a single node by name in the running game's scene tree. "
    "Returns the node's info (type, path, position, etc.) or found=false. "
    "Much faster than godotiq_game_scene_tree for checking if a specific node exists. "
    "Game must be running."
)


async def find_node(
    name: str = "",
    root: str = "",
    session_id: int | None = None,
    max_visited_nodes: int = 5000,
) -> dict:
    """Find a node by name in the running game.

    Args:
        name: Node name to search for (e.g. "BattleHudLayer").
        root: Optional root node path to search from.
        max_visited_nodes: Maximum scene nodes inspected (hard-capped game-side).

    Returns:
        Dict with found (bool), node info if found.
    """
    if not name:
        return {"error": "Missing required parameter: name"}

    bridge = await get_bridge()
    params = {"name": name, "max_visited_nodes": max_visited_nodes}
    if root:
        params["root"] = root
    if session_id is not None:
        params["session_id"] = session_id
    return await bridge.request("find_node", params=params, timeout=10.0)
