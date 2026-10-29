"""Code Intelligence tools -- dependency graph, signal map, validation, impact check.

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


# ── Teaser computation ───────────────────────────────────────────────


def _build_dependency_graph_teaser(
    session: GodotIQSession, file_path: str,
) -> dict:
    """Minimal dependency graph teaser for community preview."""
    res_path = session.resolve_file_path(file_path)
    if res_path is None:
        return {"error": "File not found or not a .gd script", "file": file_path}

    gd = session.get_script(res_path)
    if gd is None:
        return {"error": "File not found or not a .gd script", "file": file_path}

    idx = session._index
    is_autoload = res_path in idx.autoloads.values()
    direct_deps = len({r.autoload_name for r in gd.autoload_refs}) + len(gd.preload_refs)
    emits = len({e.signal_name for e in gd.signal_emissions})

    return {
        "path": res_path,
        "impact_rating": "high" if is_autoload else "low",
        "direct_dependencies": [None] * direct_deps,
        "referenced_by": [],
        "emits_signals": [None] * emits,
    }


def _build_signal_map_teaser(session: GodotIQSession) -> dict:
    """Minimal signal map teaser for community preview."""
    total_defined = sum(len(gd.signals) for gd in session._gd_scripts.values())
    total_connections = sum(
        len(gd.signal_connections) for gd in session._gd_scripts.values()
    )
    return {
        "total_signals_defined": total_defined,
        "total_connections": total_connections,
    }


def _build_validate_teaser(
    session: GodotIQSession, target: str,
) -> dict:
    """Minimal validate teaser for community preview."""
    if target == "project":
        files_checked = len(session._gd_scripts)
    else:
        files_checked = 1
    return {
        "total_issues": 0,
        "by_severity": {},
        "files_checked": files_checked,
    }


def _build_impact_check_teaser(
    session: GodotIQSession, file: str,
) -> dict:
    """Minimal impact check teaser for community preview."""
    res_path = session.resolve_file_path(file)
    if res_path is None:
        return {"error": "File not found or not a .gd script", "file": file}
    return {
        "path": res_path,
        "risk": "unknown",
        "total_files_affected": 0,
    }


# ── Stub logic (testable sync functions) ─────────────────────────────


def _stub_dependency_graph(
    session: GodotIQSession | None, file_path: str, depth: int, detail: str,
) -> dict:
    """Stub logic for godotiq_dependency_graph."""
    if session is None:
        return {"error": "No Godot project loaded"}

    detail = detail.lower() if detail else "normal"

    impl = get_pro_implementation("godotiq_dependency_graph")
    if impl is not None:
        return impl(session, file_path, depth, detail=detail)

    if session.index is None:
        return {"error": "Project index not loaded."}

    teaser = _build_dependency_graph_teaser(session, file_path)
    if "error" in teaser:
        return teaser
    return pro_unavailable_response("godotiq_dependency_graph", teaser)


def _stub_signal_map(
    session: GodotIQSession | None, scope: str, find: str, detail: str,
) -> dict:
    """Stub logic for godotiq_signal_map."""
    if session is None:
        return {"error": "No Godot project loaded"}

    detail = detail.lower() if detail else "normal"

    impl = get_pro_implementation("godotiq_signal_map")
    if impl is not None:
        return impl(session, scope, find, detail=detail)

    if session.index is None:
        return {"error": "Project index not loaded."}

    teaser = _build_signal_map_teaser(session)
    return pro_unavailable_response("godotiq_signal_map", teaser)


def _stub_impact_check(
    session: GodotIQSession | None,
    file: str, action: str, target: str,
    change_description: str, detail: str,
) -> dict:
    """Stub logic for godotiq_impact_check."""
    if session is None:
        return {"error": "No Godot project loaded"}

    detail = detail.lower() if detail else "normal"

    impl = get_pro_implementation("godotiq_impact_check")
    if impl is not None:
        return impl(session, file, action, target, change_description=change_description, detail=detail)

    if session.index is None:
        return {"error": "Project index not loaded."}

    teaser = _build_impact_check_teaser(session, file)
    if "error" in teaser:
        return teaser
    return pro_unavailable_response("godotiq_impact_check", teaser)


def _stub_validate(
    session: GodotIQSession | None, target: str, detail: str,
) -> dict:
    """Stub logic for godotiq_validate."""
    if session is None:
        return {"error": "No Godot project loaded"}

    detail = detail.lower() if detail else "normal"

    impl = get_pro_implementation("godotiq_validate")
    if impl is not None:
        return impl(session, target, detail=detail)

    if session.index is None:
        return {"error": "Project index not loaded."}

    teaser = _build_validate_teaser(session, target)
    return pro_unavailable_response("godotiq_validate", teaser)


# ── MCP tool registration ────────────────────────────────────────────


@mcp.tool(
    name="godotiq_dependency_graph",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    },
)
@guard_tool("godotiq_dependency_graph")
async def godotiq_dependency_graph(
    file: str,
    depth: int = 1,
    detail: str = "normal",
    ctx: Context = None,
) -> dict:
    """Complete dependency graph: what this file emits, who listens, what it imports, who imports it, impact rating. Call before refactoring function signatures or renaming signals. DO NOT grep the codebase — this traces the full graph in one call.

    Args:
        file: Path to .gd file (res:// or relative).
        depth: How many levels deep to trace (1 = direct deps only, 2 = deps of deps).
        detail: "brief" (signal names + refs only), "normal" (+ listeners, autoloads), "full" (+ depth_trace always).
    """
    session = ctx.request_context.lifespan_context["session"]
    return _stub_dependency_graph(session, file, depth, detail)


@mcp.tool(
    name="godotiq_signal_map",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    },
)
@guard_tool("godotiq_signal_map")
async def godotiq_signal_map(
    scope: str = "all",
    find: str = "all",
    detail: str = "normal",
    ctx: Context = None,
) -> dict:
    """Project-wide signal wiring: who emits, who listens, orphan/missing signals. DO NOT grep for .connect() calls — this traces the complete signal graph in one call. Use find="orphans" to find dead signals, "missing" to find typos.

    Args:
        scope: "all" for entire project, "autoloads" for autoload scripts only,
               or "file:res://path.gd" for a single file's signals.
        find: "all" (everything), "orphans" (emitted but no listeners), "busiest" (most connected), "missing" (emitted but never defined — likely typos).
        detail: "brief" (orphans + missing only — the actionable items), "normal" (default), "full".
    """
    session = ctx.request_context.lifespan_context["session"]
    return _stub_signal_map(session, scope, find, detail)


@mcp.tool(
    name="godotiq_impact_check",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    },
)
@guard_tool("godotiq_impact_check")
async def godotiq_impact_check(
    file: str,
    action: str,
    target: str = "",
    change_description: str = "",
    detail: str = "normal",
    ctx: Context = None,
) -> dict:
    """Predict what breaks BEFORE making a change. Returns affected files, callers, risk level, and safe alternatives. Call before renaming, removing, or changing any function/signal/class signature. DO NOT manually search for callers — this finds them all.

    Args:
        file: Path to .gd file being modified.
        action: "modify_function", "rename_signal", "add_parameter", "remove_function", "change_return_type", "rename_class".
        target: The function/signal/class being changed.
        change_description: Free-text description of the intended change (used in safe_alternative suggestions).
        detail: Output verbosity — "brief" (summary), "normal" (default), or "full" (everything).
    """
    session = ctx.request_context.lifespan_context["session"]
    return _stub_impact_check(session, file, action, target, change_description, detail)


@mcp.tool(
    name="godotiq_validate",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    },
)
@guard_tool("godotiq_validate")
async def godotiq_validate(
    target: str = "project",
    detail: str = "normal",
    ctx: Context = None,
) -> dict:
    """Convention check: missing type hints, missing class_name, orphan signals, naming violations. Run after every code change. Use on "project" for full scan or target a single file.

    Args:
        target: "project" for full scan, or path to a specific .gd file.
        detail: "brief" (severity counts only), "normal" (+ issue list), "full".
    """
    session = ctx.request_context.lifespan_context["session"]
    return _stub_validate(session, target, detail)
