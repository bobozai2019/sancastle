"""NEW2 — godotiq_state_inspect: Query runtime node properties.

Inspect node properties in the running game without screenshots.
"What state is Worker_1 in?" "How much cash?" "How many pending orders?"
Supports: direct properties, method calls (array.size()), nested access,
autoload lookup by name.
"""

from __future__ import annotations

from godotiq.bridge.session import get_bridge

TOOL_NAME = "godotiq_state_inspect"
TOOL_DESCRIPTION = (
    "Query properties of nodes in the running game. "
    "Supports: autoload lookup by name, node paths, nested properties, "
    "method calls like 'pending_orders.size()'. "
    "Lightweight — no screenshot needed. Game must be running."
)


async def state_inspect(
    queries: list[dict] | None = None,
    detail: str = "normal",
    session_id: int | None = None,
) -> dict:
    """Query runtime node properties.

    Args:
        queries: List of query dicts. Each has:
            - node: Node path (e.g. "/root/Main/Entities/Worker_1")
              OR autoload: Autoload name (e.g. "EconomyManager")
            - properties: List of property names to read.
              Supports: "cash", "position", "state", "pending_orders.size()", "position:x"
        detail: "brief" (values only), "normal" (default), or "full" (+ class name, node path).

    Returns:
        Dict with results: [{node, found, class, properties: {name: value}}]
    """
    if not queries:
        return {"error": "No queries provided", "results": []}

    params = {
        "queries": queries,
    }
    if session_id is not None:
        params["session_id"] = session_id

    bridge = await get_bridge()
    result = await bridge.request("state_inspect", params=params, timeout=5.0)

    detail = (detail or "normal").lower()
    if detail == "brief":
        brief_results = []
        for r in result.get("results", []):
            brief_results.append({
                "properties": r.get("properties", {}),
            })
        return {"results": brief_results}

    return result
