"""Check GDScript files for compilation/parse errors via the Godot bridge."""

from __future__ import annotations

from pathlib import PurePosixPath

from godotiq.bridge.session import get_bridge


async def check_errors(scope: str = "scene") -> dict:
    """Check GDScript files for compilation errors.

    Args:
        scope: "scene" (current scene + autoloads), "project" (all .gd files),
               or a "res://path/to/script.gd" (single file).

    Returns:
        Dict with errors array, total count, scripts_checked, and scope.
    """
    bridge = await get_bridge()
    normalized_scope = _normalize_scope(scope)
    await _refresh_script_scope(bridge, normalized_scope)
    result = await bridge.request("check_errors", params={"scope": normalized_scope})
    _annotate_confidence(result)
    return result


def _normalize_scope(scope: str) -> str:
    """Normalize single-file scopes to res:// paths for bridge calls."""
    if scope in {"scene", "project"}:
        return scope
    if scope.startswith("res://"):
        return scope
    return f"res://{scope.lstrip('/')}"


async def _refresh_script_scope(bridge, scope: str) -> None:
    """Best-effort reload for single-script scopes to avoid stale parse results."""
    if scope in {"scene", "project"}:
        return
    if PurePosixPath(scope.removeprefix("res://")).suffix.lower() != ".gd":
        return
    try:
        await bridge.request("reload_script", params={"path": scope})
    except Exception:
        pass


def _annotate_confidence(result: dict) -> None:
    """Add confidence annotations to error entries in-place.

    Errors at line 0 or with missing line are likely false positives from
    Godot's cache/reload mechanism and get confidence "low". All others
    get "high". A top-level note is added when any low-confidence error exists.
    """
    errors = result.get("errors")
    if not isinstance(errors, list):
        return
    has_low = False
    for err in errors:
        line = err.get("line")
        if not isinstance(line, int) or line <= 0:
            err["confidence"] = "low"
            has_low = True
        else:
            err["confidence"] = "high"
    if has_low:
        result["note"] = (
            "line 0 errors are often false positives "
            "\u2014 try reloading the scene"
        )
