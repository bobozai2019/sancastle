"""Project Memory tools — project summary and file context.

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


def _read_main_scene(session: GodotIQSession) -> str:
    """Read run/main_scene from project.godot."""
    godot_file = session.project_root / "project.godot"
    if not godot_file.exists():
        return ""
    in_application = False
    for line in godot_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("[") and line.endswith("]"):
            in_application = line == "[application]"
            continue
        if in_application and line.startswith("run/main_scene="):
            value = line.split("=", 1)[1].strip().strip('"')
            return value
    return ""


def _build_brief(session: GodotIQSession) -> dict:
    """Build brief-level project summary (teaser data for community preview)."""
    idx = session.index
    return {
        "project_name": idx.project_name,
        "engine": session.config.project.get("engine", "godot_4"),
        "type": session.config.project.get("type", "unknown"),
        "counts": {
            "scenes": idx.total_scenes,
            "scripts": idx.total_scripts,
            "assets": idx.total_assets,
        },
        "autoloads": list(idx.autoloads.keys()),
    }


def _build_file_teaser(session: GodotIQSession, file_path: str) -> dict:
    """Build minimal file context for community preview.

    Returns enough data for _preview_file_context() in license.py,
    or an error dict if the file is not found / unsupported.
    """
    res_path = session.resolve_file_path(file_path)
    if res_path is None:
        return {"error": "File not found", "file": file_path}

    # Try as GDScript
    gd = session.get_script(res_path)
    if gd is not None:
        func_count = sum(1 for f in gd.functions if not f.is_private)
        return {
            "path": res_path,
            "type": "gdscript",
            "class_name": gd.class_name,
            "extends": gd.extends,
            "public_api": {"functions": [None] * func_count},
            "signals_defined": [s.name for s in gd.signals],
        }

    # Try as scene
    scene = session.get_scene(res_path)
    if scene is not None:
        return {
            "path": res_path,
            "type": "scene",
            "total_nodes": len(scene.nodes),
            "root_type": scene.root.type if scene.root else "",
            "scripts_used": scene.get_all_scripts(),
        }

    return {
        "error": "Unsupported file type. Only .gd and .tscn files are supported.",
        "file": res_path,
    }


# ── Stub logic (testable sync functions) ─────────────────────────────


def _stub_project_summary(session: GodotIQSession | None, detail: str) -> dict:
    """Stub logic for godotiq_project_summary.

    Delegates to Pro bundle if available, otherwise returns community preview.
    """
    if session is None:
        return {"error": "No Godot project loaded. Set GODOTIQ_PROJECT_ROOT or run from project directory."}

    detail = detail.lower() if detail else "normal"

    impl = get_pro_implementation("godotiq_project_summary")
    if impl is not None:
        return impl(session, detail)

    if session.index is None:
        return {"error": "Project index not loaded."}

    teaser = _build_brief(session)
    return pro_unavailable_response("godotiq_project_summary", teaser)


def _stub_file_context(
    session: GodotIQSession | None, file_path: str, detail: str,
) -> dict:
    """Stub logic for godotiq_file_context.

    Delegates to Pro bundle if available, otherwise returns community preview.
    """
    if session is None:
        return {"error": "No Godot project loaded"}

    detail = detail.lower() if detail else "normal"

    impl = get_pro_implementation("godotiq_file_context")
    if impl is not None:
        return impl(session, file_path, detail=detail)

    if session.index is None:
        return {"error": "Project index not loaded."}

    teaser = _build_file_teaser(session, file_path)
    if "error" in teaser:
        return teaser
    return pro_unavailable_response("godotiq_file_context", teaser)


# ── MCP tool registration ────────────────────────────────────────────


@mcp.tool(
    name="godotiq_project_summary",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    },
)
@guard_tool("godotiq_project_summary")
async def godotiq_project_summary(
    detail: str = "normal",
    ctx: Context = None,
) -> dict:
    """Call FIRST in every session. Architecture, autoloads, conventions, file counts. Replaces manual project exploration — one call gives full context. Use detail="brief" for counts only.

    Args:
        detail: "brief" (counts + autoload names), "normal" (+ architecture), "full" (+ scene structure, signal health).
    """
    session = ctx.request_context.lifespan_context["session"]
    return _stub_project_summary(session, detail)


@mcp.tool(
    name="godotiq_file_context",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    },
)
@guard_tool("godotiq_file_context")
async def godotiq_file_context(
    file: str,
    detail: str = "normal",
    ctx: Context = None,
) -> dict:
    """Call BEFORE editing any file. Returns public API, dependencies, signals, who imports this file, scene usage. Without this you risk breaking callers. DO NOT read .gd/.tscn files directly — this gives structured cross-referenced data.

    Args:
        file: Path to file (res:// or relative). Works for .gd scripts and .tscn scenes.
        detail: "brief" (public API only), "normal" (+ deps, signals, safety), "full".
    """
    session = ctx.request_context.lifespan_context["session"]
    return _stub_file_context(session, file, detail)
