"""Scene tree tool -- read the live editor scene tree via the bridge."""

from __future__ import annotations

from godotiq.bridge.session import get_bridge

DEFAULT_INCLUDE: list[str] = ["transform", "script", "groups", "visibility"]


async def scene_tree(
    root: str = "",
    depth: int = 3,
    filter_type: str = "",
    include: list[str] | None = None,
    detail: str = "normal",
) -> dict:
    """Get the live scene tree from the Godot editor.

    Args:
        root: Optional node path to start from (e.g. "Level/Enemies").
              Empty string means the edited scene root.
        depth: Maximum tree depth to return. Clamped to [1, 10].
        filter_type: Only include nodes of this type (e.g. "MeshInstance3D").
                     Empty string means all types.
        include: Which optional data fields to include per node.
                 Defaults to ["transform", "script", "groups", "visibility"].
        detail: "brief", "normal", or "full".

    Returns:
        Dict with root, scene_path, total_nodes, returned_nodes, and tree.
    """
    depth = max(1, min(10, depth))

    if include is None:
        include = list(DEFAULT_INCLUDE)

    bridge = await get_bridge()
    result = await bridge.request(
        "scene_tree",
        params={
            "root": root,
            "depth": depth,
            "filter_type": filter_type,
            "include": include,
        },
    )

    detail = (detail or "normal").lower()
    if detail == "brief":
        tree = result.get("tree", [])
        return {
            "root": result.get("root"),
            "total_nodes": result.get("total_nodes"),
            "returned_nodes": min(result.get("returned_nodes", 0), 20),
            "children": [
                {"name": c.get("n"), "type": c.get("t")}
                for c in tree[:20]
            ],
        }

    return result
