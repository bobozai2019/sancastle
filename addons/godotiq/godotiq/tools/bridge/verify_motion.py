"""Verify a node property changes over time (proves movement/animation)."""

from __future__ import annotations

import asyncio

from godotiq.bridge.session import get_bridge


async def verify_motion(
    node: str,
    property_name: str = "position",
    duration: float = 2.0,
    session_id: int | None = None,
) -> dict:
    """Verify a node property changes over time (proves movement/animation).

    Takes two state_inspect snapshots separated by a sleep and compares values.

    Args:
        node: Node path or name to inspect.
        property_name: Property to monitor (default "position").
        duration: Seconds to wait between snapshots (default 2.0).

    Returns:
        Dict with verdict ("MOVING", "STATIC", or "ERROR"), before/after values.
    """
    bridge = await get_bridge()

    # Check game is running
    ping = await bridge.request("ping")
    if not ping.get("game_running", False):
        return {"error": "Game is not running. Start it with godotiq_run first."}

    # First snapshot
    query = {"queries": [{"node": node, "properties": [property_name]}]}
    if session_id is not None:
        query["session_id"] = session_id
    snap1 = await bridge.request("state_inspect", params=query)
    results1 = snap1.get("results", [])
    if not results1 or not results1[0].get("found", False):
        return {"error": f"Node '{node}' not found or property '{property_name}' not accessible"}

    before = str(results1[0].get("properties", {}).get(property_name, ""))

    # Wait
    await asyncio.sleep(duration)

    # Second snapshot
    snap2 = await bridge.request("state_inspect", params=query)
    results2 = snap2.get("results", [])
    if not results2 or not results2[0].get("found", False):
        return {
            "node": node,
            "property_name": property_name,
            "verdict": "ERROR",
            "error": "Game may have stopped during verification",
        }

    after = str(results2[0].get("properties", {}).get(property_name, ""))

    changed = before != after
    return {
        "node": node,
        "property_name": property_name,
        "before": before,
        "after": after,
        "changed": changed,
        "verdict": "MOVING" if changed else "STATIC",
        "duration_seconds": duration,
    }
