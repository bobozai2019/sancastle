"""Persistent node property monitoring."""

from __future__ import annotations

from ...bridge.session import get_bridge


async def watch(
    action: str = "read",
    watches: list[dict] | None = None,
    sample_interval_ms: int = 500,
    detail: str = "normal",
    session_id: int | None = None,
) -> dict:
    """Control the watch system in the running game.

    Args:
        action: "start", "stop", "read", or "clear".
        watches: For "start" — list of {node: str, properties: [str]} to watch.
        sample_interval_ms: Sampling interval in ms (default 500, min 50).
        detail: "brief" (last 10 events), "normal" (default), or "full".

    Returns:
        Dict with action confirmation, events (for read), watches_active count.
    """
    params: dict = {"action": action}

    if action == "start":
        if not watches:
            return {"error": "No watches provided for 'start' action"}
        params["watches"] = watches
        params["sample_interval_ms"] = max(50, sample_interval_ms)
    if session_id is not None:
        params["session_id"] = session_id

    bridge = await get_bridge()
    result = await bridge.request("watch", params=params, timeout=5.0)

    detail = (detail or "normal").lower()
    if detail == "brief" and action == "read":
        events = result.get("events", [])
        result["events"] = events[-10:]

    return result
