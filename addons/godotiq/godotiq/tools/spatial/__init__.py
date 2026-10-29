"""Spatial Intelligence tools — scene maps, transforms, spatial queries.

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


ALL_CHECKS = [
    "floating_objects",
    "scale_mismatch",
    "z_fighting",
    "empty_markers",
    "overlapping",
    "extreme_positions",
]


# ── Stub logic (testable sync functions) ─────────────────────────────


def _stub_scene_map(
    session: GodotIQSession | None, scene: str, focus: str | None,
    radius: float, include: list[str] | None, detail: str,
) -> dict:
    """Stub logic for godotiq_scene_map."""
    if session is None:
        return {"error": "No Godot project loaded"}

    detail = detail.lower() if detail else "normal"

    impl = get_pro_implementation("godotiq_scene_map")
    if impl is not None:
        return impl(session, scene, focus, radius, include, detail)

    if session.index is None:
        return {"error": "Project index not loaded."}

    spatial = session.resolve_scene_spatial(scene)
    if spatial is None:
        return {"error": "Scene not found", "scene": scene}

    resolved, _world_nodes = spatial
    teaser = {
        "total_nodes": resolved.total_nodes,
        "nodes": [],
        "spatial_summary": {"bounds": {}},
    }
    return pro_unavailable_response("godotiq_scene_map", teaser)


def _stub_spatial_audit(
    session: GodotIQSession | None, scene: str,
    checks: list[str] | None, min_severity: str, detail: str,
) -> dict:
    """Stub logic for godotiq_spatial_audit."""
    if session is None:
        return {"error": "No Godot project loaded"}

    detail = detail.lower() if detail else "normal"

    impl = get_pro_implementation("godotiq_spatial_audit")
    if impl is not None:
        return impl(session, scene, checks, min_severity, detail)

    if session.index is None:
        return {"error": "Project index not loaded."}

    teaser = {
        "total_issues": 0,
        "by_severity": {},
        "checks_run": list(ALL_CHECKS),
    }
    return pro_unavailable_response("godotiq_spatial_audit", teaser)


def _stub_placement(
    session: GodotIQSession | None, scene: str, near: str,
    near_position: list[float] | None, object_type: str,
    constraints: dict | None, max_suggestions: int, detail: str,
) -> dict:
    """Stub logic for godotiq_placement."""
    if session is None:
        return {"error": "No Godot project loaded"}

    detail = detail.lower() if detail else "normal"

    impl = get_pro_implementation("godotiq_placement")
    if impl is not None:
        return impl(session, scene, near, near_position, object_type, constraints, max_suggestions, detail)

    if session.index is None:
        return {"error": "Project index not loaded."}

    teaser = {
        "candidates_evaluated": 0,
        "suggestions": [],
        "excluded_zones": [],
    }
    return pro_unavailable_response("godotiq_placement", teaser)


# ── MCP tool registration ────────────────────────────────────────────


@mcp.tool(
    name="godotiq_scene_map",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    },
)
@guard_tool("godotiq_scene_map")
async def godotiq_scene_map(
    scene: str,
    focus: str | None = None,
    radius: float = 5.0,
    include: list[str] | None = None,
    detail: str = "normal",
    ctx: Context = None,
) -> dict:
    """Spatial understanding of a .tscn scene: positions, distances, directions, bounds. ALWAYS call before placing or moving 3D objects — never guess positions. DO NOT read .tscn files directly — they are unreadable resource format. Use focus + radius to zoom into an area.

    Args:
        scene: Path to .tscn file (res:// or relative).
        focus: Node name or path to center the view on. Returns nearby nodes sorted by distance.
        radius: Distance filter around focus node (meters, default 5.0). Only used with focus.
        include: List of node types or groups to include (e.g. ["MeshInstance3D", "enemies"]).
        detail: "brief" (name/type/position only), "normal" (+ groups, scripts, bounds), "full" (+ properties, distance matrix).
    """
    session = ctx.request_context.lifespan_context["session"]
    return _stub_scene_map(session, scene, focus, radius, include, detail)


@mcp.tool(
    name="godotiq_spatial_audit",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    },
)
@guard_tool("godotiq_spatial_audit")
async def godotiq_spatial_audit(
    scene: str,
    checks: list[str] | None = None,
    min_severity: str = "warning",
    detail: str = "normal",
    ctx: Context = None,
) -> dict:
    """Automated 3D scene linter: floating objects, scale mismatches, z-fighting, overlapping instances, extreme positions. Run on any scene to catch spatial issues before they become visual bugs. Use detail="brief" for only real problems.

    Args:
        scene: Path to .tscn file (res:// or relative).
        checks: Specific checks to run (default all 6): "floating_objects", "scale_mismatch", "z_fighting", "empty_markers", "overlapping", "extreme_positions".
        min_severity: Minimum severity: "warning" (default, filters info), "info" (everything), "critical".
        detail: "brief" (critical + warning only), "normal" (excludes cosmetic z-fighting/overlapping), "full" (everything).
    """
    session = ctx.request_context.lifespan_context["session"]
    return _stub_spatial_audit(session, scene, checks, min_severity, detail)


@mcp.tool(
    name="godotiq_placement",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    },
)
@guard_tool("godotiq_placement")
async def godotiq_placement(
    scene: str = "",
    near: str = "",
    near_position: list[float] | None = None,
    object_type: str = "",
    constraints: dict | None = None,
    max_suggestions: int = 3,
    detail: str = "normal",
    ctx: Context = None,
) -> dict:
    """Find safe placement positions for new objects. DO NOT guess positions or manually calculate coordinates. Checks Marker3D slots first (designer-intended spots, highest confidence), then grid-searches nearby space with wall/overlap validation. Returns up to 3 suggestions with confidence scores.

    Args:
        scene: Scene file path (.tscn). Uses project main scene if empty.
        near: Node name to place near (e.g. "PrinterSlot_P3").
        near_position: [x, y, z] coordinates to place near (alternative to 'near').
        object_type: Semantic type hint (e.g. "printer", "shelf") — finds similar objects for scale/rotation reference.
        constraints: {on_floor: bool, min_wall_distance: float, min_object_distance: float, face_direction: str, marker_group: str}.
        max_suggestions: Maximum number of suggestions (default 3).
        detail: Output verbosity — "brief" (summary), "normal" (default), or "full" (everything).
    """
    session = ctx.request_context.lifespan_context["session"]
    return _stub_placement(session, scene, near, near_position, object_type, constraints, max_suggestions, detail)
