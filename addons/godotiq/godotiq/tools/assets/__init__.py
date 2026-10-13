"""Asset Intelligence tools — inventory, scaling, validation.

These tools are Pro stubs that delegate to the Pro bundle when available.
When the bundle is unavailable, ``pro_unavailable_response`` decides:
no license key configured → community preview; key configured but Pro
entitlement broken → explicit licensing error (no silent downgrade).
"""

from __future__ import annotations

from pathlib import PurePosixPath

from mcp.server.fastmcp import Context

from godotiq.license import pro_unavailable_response
from godotiq.pro_loader import get_pro_implementation
from godotiq.server import mcp
from godotiq.session import GodotIQSession
from godotiq.tool_runtime import guard_tool


# Extension -> category mapping (needed for teaser computation)
_CATEGORY_MAP: dict[str, str] = {
    ".glb": "models",
    ".gltf": "models",
    ".obj": "models",
    ".fbx": "models",
    ".png": "textures",
    ".jpg": "textures",
    ".jpeg": "textures",
    ".svg": "textures",
    ".webp": "textures",
    ".wav": "audio",
    ".ogg": "audio",
    ".mp3": "audio",
    ".ttf": "fonts",
    ".otf": "fonts",
    ".woff": "fonts",
    ".tscn": "scenes",
    ".scn": "scenes",
    ".tres": "resources",
    ".res": "resources",
    ".gdshader": "shaders",
    ".shader": "shaders",
}


def _categorize(path: str) -> str:
    """Determine asset category from file extension."""
    ext = PurePosixPath(path).suffix.lower()
    return _CATEGORY_MAP.get(ext, "other")


# ── Stub logic (testable sync functions) ─────────────────────────────


def _stub_asset_registry(
    session: GodotIQSession | None, category: str, check_usage: bool,
    detail: str, path_filter: str, max_results: int,
) -> dict:
    """Stub logic for godotiq_asset_registry."""
    if session is None:
        return {"error": "No Godot project loaded"}

    detail = detail.lower() if detail else "normal"

    impl = get_pro_implementation("godotiq_asset_registry")
    if impl is not None:
        return impl(session, category, check_usage, detail, path_filter, max_results)

    if session.index is None:
        return {"error": "Project index not loaded."}

    # Compute teaser: asset counts by category
    by_category: dict[str, int] = {}
    total = 0
    for asset_path in session._index.assets:
        cat = _categorize(asset_path)
        if category != "all" and cat != category:
            continue
        if path_filter and path_filter not in asset_path:
            continue
        by_category[cat] = by_category.get(cat, 0) + 1
        total += 1

    teaser = {
        "total_assets": total,
        "by_category": by_category,
        "unused_count": 0,
    }
    return pro_unavailable_response("godotiq_asset_registry", teaser)


def _stub_suggest_scale(
    session: GodotIQSession | None, scene: str, model: str | None,
    near_node: str | None, intended_use: str, detail: str,
) -> dict:
    """Stub logic for godotiq_suggest_scale."""
    if session is None:
        return {"error": "No Godot project loaded"}

    if intended_use is None:
        intended_use = ""
    if model is not None and not model.strip():
        model = None
    if model is None and not intended_use:
        return {"error": "Either 'model' or 'intended_use' must be provided"}

    detail = detail.lower() if detail else "normal"

    impl = get_pro_implementation("godotiq_suggest_scale")
    if impl is not None:
        return impl(session, scene, model, near_node, intended_use, detail)

    if session.index is None:
        return {"error": "Project index not loaded."}

    teaser = {
        "match_tier": "unknown",
        "reference_models": [],
    }
    return pro_unavailable_response("godotiq_suggest_scale", teaser)


# ── MCP tool registration ────────────────────────────────────────────


@mcp.tool(
    name="godotiq_asset_registry",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    },
)
@guard_tool("godotiq_asset_registry")
async def godotiq_asset_registry(
    category: str = "all",
    check_usage: bool = True,
    detail: str = "normal",
    path_filter: str = "",
    max_results: int = 0,
    ctx: Context = None,
) -> dict:
    """Complete asset inventory: find unused assets, missing references, assets by type. Use to audit project assets and clean up bloat.

    Args:
        category: "all", "models", "textures", "audio", "scenes", "scripts", etc.
        check_usage: Check which assets are actually used in scenes (default true).
        detail: "brief" (counts only), "normal" (counts + top 20 unused), "full" (everything).
        path_filter: Filter assets by path substring (e.g. "kenney_furniturekit").
        max_results: Max number of assets to return (0 = no limit).
    """
    session = ctx.request_context.lifespan_context["session"]
    return _stub_asset_registry(session, category, check_usage, detail, path_filter, max_results)


@mcp.tool(
    name="godotiq_suggest_scale",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    },
)
@guard_tool("godotiq_suggest_scale")
async def godotiq_suggest_scale(
    scene: str,
    model: str | None = None,
    near_node: str | None = None,
    intended_use: str = "",
    detail: str = "normal",
    ctx: Context = None,
) -> dict:
    """Recommend scale + position for a model based on similar assets in the scene. Never guess scales — this analyzes existing objects and suggests matching values. Respects asset_origins from .godotiq.json.

    Args:
        scene: Path to .tscn file (res:// or relative).
        model: Model asset path (res://). Omit for reference mode (returns scale stats for matching nodes).
        near_node: Node name to suggest position near.
        intended_use: Semantic hint (e.g. "printer", "shelf"). Required when model is omitted.
        detail: Output verbosity — "brief" (summary), "normal" (default), or "full" (everything).
    """
    session = ctx.request_context.lifespan_context["session"]
    return _stub_suggest_scale(session, scene, model, near_node, intended_use, detail)
