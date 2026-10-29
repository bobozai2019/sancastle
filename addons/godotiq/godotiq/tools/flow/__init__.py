"""Flow and Debug tools — execution flow, error tracking.

These tools are Pro stubs that delegate to the Pro bundle when available.
When the bundle is unavailable, ``pro_unavailable_response`` decides:
no license key configured → community preview; key configured but Pro
entitlement broken → explicit licensing error (no silent downgrade).
"""

from __future__ import annotations

from mcp.server.fastmcp import Context

from godotiq.license import pro_unavailable_response
from godotiq.pro_loader import get_pro_implementation
from godotiq.server import mcp
from godotiq.session import GodotIQSession
from godotiq.tool_runtime import guard_tool


# ── Stub logic (testable sync function) ──────────────────────────────


def _stub_trace_flow(
    session: GodotIQSession | None, trigger: str, depth: int, detail: str,
) -> dict:
    """Stub logic for godotiq_trace_flow."""
    if session is None:
        return {"error": "No Godot project loaded"}

    detail = detail.lower() if detail else "normal"

    impl = get_pro_implementation("godotiq_trace_flow")
    if impl is not None:
        return impl(session, trigger, depth, detail)

    if session.index is None:
        return {"error": "Project index not loaded."}

    teaser = {
        "entry": trigger,
        "files_involved": len(session._gd_scripts),
        "total_steps": 0,
        "failure_points": [],
    }
    return pro_unavailable_response("godotiq_trace_flow", teaser)


# ── MCP tool registration ────────────────────────────────────────────


@mcp.tool(
    name="godotiq_trace_flow",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    },
)
@guard_tool("godotiq_trace_flow")
async def godotiq_trace_flow(
    trigger: str,
    depth: int = 10,
    detail: str = "normal",
    ctx: Context = None,
) -> dict:
    """Trace execution flow from a function or signal through the entire codebase. "What happens when X is called?" Returns the chain of calls, signal emissions, and failure points. DO NOT manually trace call chains — this does it automatically.

    Args:
        trigger: Exact function or signal name to trace (e.g. "start_print_job", "order_completed").
        depth: Max recursion depth (default 10).
        detail: "brief" (steps only — file + function), "normal" (+ line numbers, failure points), "full".
    """
    session = ctx.request_context.lifespan_context["session"]
    return _stub_trace_flow(session, trigger, depth, detail)
