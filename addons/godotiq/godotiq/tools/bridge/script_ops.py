"""Script operations tool -- filesystem-based script reading, writing, patching, and creation."""

from __future__ import annotations

import os
import re
from pathlib import Path

from godotiq.config import GodotIQConfig, load_config
from godotiq.session import discover_project_root


async def _try_reload_script(rel_path: str) -> None:
    """Best-effort script reload via bridge. Silent on failure."""
    if not rel_path.endswith(".gd"):
        return
    try:
        from godotiq.bridge.session import get_bridge_or_none

        bridge = await get_bridge_or_none()
        if bridge is None:
            return
        res_path = f"res://{rel_path}"
        await bridge.request("reload_script", params={"path": res_path})
    except Exception:
        pass


def _get_root(project_root: str | Path | None = None) -> Path:
    """Resolve the active project root path."""
    if project_root is not None:
        return Path(project_root).resolve()

    root = os.environ.get("GODOTIQ_PROJECT_ROOT")
    if root:
        return Path(root).resolve()

    discovered = discover_project_root()
    if discovered is None:
        raise ValueError("Godot project root not found")
    return discovered.resolve()


def _get_config(root: Path, config: GodotIQConfig | None = None) -> GodotIQConfig:
    """Resolve the active project config."""
    if config is not None:
        return config
    return load_config(str(root / ".godotiq.json"))


def _resolve_path(path: str, root: Path | None = None) -> Path:
    """Resolve a res:// or relative path to absolute filesystem path.

    Raises ValueError if the resolved path is outside the project root.
    """
    if root is None:
        root = _get_root()

    if path.startswith("res://"):
        path = path[len("res://"):]

    resolved = (root / path).resolve()

    try:
        resolved.relative_to(root)
    except ValueError:
        raise ValueError(f"Path resolves outside project root: {path}")

    return resolved


def _is_protected(path: str, config: GodotIQConfig | None = None) -> bool:
    """Check if path is protected (should not be modified)."""
    if config is None:
        config = GodotIQConfig()
    normalized = Path(path.replace("\\", "/")).as_posix()
    if normalized == ".godotiq" or normalized.startswith(".godotiq/"):
        return True
    return config.is_file_protected(normalized)


def _find_line_number(text: str, search: str) -> int:
    """Find the 1-based line number where search string starts.

    Returns -1 if not found.
    """
    idx = text.find(search)
    if idx == -1:
        return -1
    return text[:idx].count("\n") + 1


def _validate_gdscript(content: str, path: str) -> list[dict]:
    """Basic GDScript convention validation.

    Currently checks for var declarations without type hints.

    Returns:
        List of issue dicts with severity, rule, line, and detail keys.
    """
    issues: list[dict] = []
    lines = content.split("\n")

    for i, line in enumerate(lines, start=1):
        stripped = line.strip()

        # Skip comments, empty lines, and @onready vars
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("@onready"):
            continue

        # Check for var declarations without type hints
        if re.match(r"^var\s+\w+\s*=", stripped):
            issues.append({
                "severity": "warning",
                "rule": "type_hint",
                "line": i,
                "detail": f"Variable declaration without type hint: {stripped}",
            })

    return issues


async def script_ops(
    op: str = "read",
    path: str = "",
    content: str = "",
    patches: list[dict] | None = None,
    validate_before_write: bool = True,
    auto_fix: bool = False,
    dry_run: bool = False,
    project_root: str | Path | None = None,
    config: GodotIQConfig | None = None,
) -> dict:
    """Read, write, patch, or create a script file.

    Args:
        op: Operation mode - "read", "write", "patch", or "create".
        path: File path (res:// or relative to project root).
        content: File content for write/create modes.
        patches: List of {search, replace} dicts for patch mode.
        validate_before_write: Run GDScript validation before writing.
        auto_fix: Reserved for future auto-fix functionality.
        dry_run: If True, validate but don't write.

    Returns:
        Dict with status and operation-specific results.
    """
    if not path:
        return {"status": "ERROR", "error": "Path is required."}

    try:
        root = _get_root(project_root)
        resolved_config = _get_config(root, config)
        resolved = _resolve_path(path, root)
    except ValueError as e:
        return {"status": "ERROR", "error": str(e)}

    rel_path = path.removeprefix("res://") if path.startswith("res://") else path

    if op == "read":
        return await _op_read(resolved, rel_path)
    elif op == "write":
        return await _op_write(
            resolved, rel_path, content, validate_before_write, dry_run, resolved_config
        )
    elif op == "patch":
        return await _op_patch(
            resolved, rel_path, patches or [], validate_before_write, dry_run, resolved_config
        )
    elif op == "create":
        return await _op_create(resolved, rel_path, content, dry_run, resolved_config)
    else:
        return {"status": "ERROR", "error": f"Unknown operation: {op}"}


async def _op_read(resolved: Path, rel_path: str) -> dict:
    """Read a script file."""
    if not resolved.exists():
        return {"status": "ERROR", "error": f"Not found: {rel_path}"}

    text = resolved.read_text(encoding="utf-8")
    line_count = text.count("\n")
    if text and not text.endswith("\n"):
        line_count += 1

    return {
        "status": "OK",
        "path": rel_path,
        "content": text,
        "lines": line_count,
        "size_bytes": resolved.stat().st_size,
    }


async def _op_write(
    resolved: Path, rel_path: str, content: str,
    validate_before_write: bool, dry_run: bool,
    config: GodotIQConfig | None = None,
) -> dict:
    """Write a script file."""
    if config is None:
        config = _get_config(_get_root())
    if _is_protected(rel_path, config):
        return {"status": "BLOCKED", "error": f"Protected file: {rel_path}"}

    if not content:
        return {"status": "ERROR", "error": "Content is required for write."}

    validation_issues: list[dict] = []
    if validate_before_write:
        validation_issues = _validate_gdscript(content, rel_path)

    line_count = content.count("\n")
    if content and not content.endswith("\n"):
        line_count += 1

    if dry_run:
        return {
            "status": "DRY_RUN",
            "path": rel_path,
            "lines": line_count,
            "validation_issues": validation_issues,
            "written": False,
        }

    resolved.parent.mkdir(parents=True, exist_ok=True)
    resolved.write_text(content, encoding="utf-8")

    if rel_path.endswith(".gd"):
        await _try_reload_script(rel_path)

    return {
        "status": "OK",
        "path": rel_path,
        "lines": line_count,
        "validation_issues": validation_issues,
        "written": True,
    }


async def _op_patch(
    resolved: Path, rel_path: str, patches: list[dict],
    validate_before_write: bool, dry_run: bool,
    config: GodotIQConfig | None = None,
) -> dict:
    """Patch a script file with find-and-replace operations."""
    if config is None:
        config = _get_config(_get_root())
    if _is_protected(rel_path, config):
        return {"status": "BLOCKED", "error": f"Protected file: {rel_path}"}

    if not resolved.exists():
        return {"status": "ERROR", "error": f"Not found: {rel_path}"}

    if not patches:
        return {"status": "ERROR", "error": "No patches provided.", "written": False}

    text = resolved.read_text(encoding="utf-8")
    applied: list[dict] = []
    failed: list[dict] = []

    for patch in patches:
        search = patch.get("search", "")
        replace = patch.get("replace", "")

        if not search:
            failed.append({"search": search, "error": "Empty search string."})
            continue

        count = text.count(search)
        if count == 0:
            failed.append({"search": search, "error": "Not found in file."})
            continue
        if count > 1:
            failed.append({"search": search, "error": f"Ambiguous: found {count} matches."})
            continue

        line = _find_line_number(text, search)
        text = text.replace(search, replace, 1)
        applied.append({"search": search, "replace": replace, "line": line})

    if failed and not applied:
        return {
            "status": "ERROR",
            "path": rel_path,
            "applied": applied,
            "failed": failed,
            "written": False,
        }

    if failed:
        return {
            "status": "PARTIAL",
            "path": rel_path,
            "applied": applied,
            "failed": failed,
            "written": False,
        }

    validation_issues: list[dict] = []
    if validate_before_write:
        validation_issues = _validate_gdscript(text, rel_path)

    if dry_run:
        return {
            "status": "DRY_RUN",
            "path": rel_path,
            "applied": applied,
            "failed": failed,
            "validation_issues": validation_issues,
            "written": False,
        }

    resolved.write_text(text, encoding="utf-8")
    if rel_path.endswith(".gd"):
        await _try_reload_script(rel_path)

    return {
        "status": "OK",
        "path": rel_path,
        "applied": applied,
        "failed": failed,
        "validation_issues": validation_issues,
        "written": True,
    }


async def _op_create(
    resolved: Path,
    rel_path: str,
    content: str,
    dry_run: bool = False,
    config: GodotIQConfig | None = None,
) -> dict:
    """Create a new script file."""
    if config is None:
        config = _get_config(_get_root())
    if _is_protected(rel_path, config):
        return {"status": "BLOCKED", "error": f"Protected file: {rel_path}"}

    if resolved.exists():
        return {"status": "ERROR", "error": f"File already exists: {rel_path}"}

    if not content:
        return {"status": "ERROR", "error": "Content is required for create."}

    line_count = content.count("\n")
    if content and not content.endswith("\n"):
        line_count += 1

    if dry_run:
        return {
            "status": "DRY_RUN",
            "path": rel_path,
            "created": False,
            "lines": line_count,
        }

    resolved.parent.mkdir(parents=True, exist_ok=True)
    resolved.write_text(content, encoding="utf-8")

    if rel_path.endswith(".gd"):
        await _try_reload_script(rel_path)

    return {
        "status": "OK",
        "path": rel_path,
        "created": True,
        "lines": line_count,
    }
