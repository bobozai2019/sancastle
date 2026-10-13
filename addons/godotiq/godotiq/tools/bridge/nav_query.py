"""Live pathfinding via NavigationServer3D."""

from __future__ import annotations

from ...bridge.session import get_bridge


async def nav_query(
    from_node: str = "",
    to_node: str = "",
    from_position: list[float] | None = None,
    to_position: list[float] | None = None,
    optimize: bool = True,
    detail: str = "normal",
    session_id: int | None = None,
) -> dict:
    """Query navigation path between two points in the running game.

    Args:
        from_node: Source node name (uses its global_position).
        to_node: Target node name (uses its global_position).
        from_position: Source coordinates [x, y, z] (alternative to from_node).
        to_position: Target coordinates [x, y, z] (alternative to to_node).
        optimize: Optimize the path (default True).
        detail: "brief" (reachable + distance only), "normal" (default), or "full".

    Returns:
        Dict with reachable, distance, direct_distance, efficiency_ratio,
        path_points, waypoint_count, from/to_on_navmesh.
    """
    params: dict = {"optimize": optimize}

    if from_node:
        params["from_node"] = from_node
    elif from_position:
        params["from_position"] = from_position
    else:
        return {"error": "Provide either from_node or from_position"}

    if to_node:
        params["to_node"] = to_node
    elif to_position:
        params["to_position"] = to_position
    else:
        return {"error": "Provide either to_node or to_position"}
    if session_id is not None:
        params["session_id"] = session_id

    bridge = await get_bridge()
    result = await bridge.request("nav_query", params=params, timeout=10.0)

    detail = (detail or "normal").lower()
    if detail == "brief":
        return {
            "reachable": result.get("reachable"),
            "distance": result.get("distance"),
        }

    return result
