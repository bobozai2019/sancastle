"""File operations tool — filesystem operations within the Godot project."""

from __future__ import annotations

import os
import shutil
from pathlib import Path

from godotiq.config import GodotIQConfig, load_config
from godotiq.session import discover_project_root

TYPE_FILTERS: dict[str, set[str]] = {
    "scenes": {".tscn", ".scn"},
    "scripts": {".gd"},
    "images": {".png", ".jpg", ".jpeg", ".webp", ".svg", ".bmp", ".tga"},
    "audio": {".wav", ".ogg", ".mp3"},
    "fonts": {".ttf", ".otf", ".woff", ".woff2"},
    "models": {".glb", ".gltf", ".obj", ".fbx", ".dae"},
    "shaders": {".gdshader"},
    "resources": {".tres", ".res"},
}

EXCLUDED_DIRS: set[str] = {
    ".godot",
    ".godotiq",
    ".git",
    "__pycache__",
    "node_modules",
    ".import",
}

MAX_SEARCH_MATCHES: int = 50


def _get_root(project_root: str | Path | None = None) -> Path:
    """Resolve the active project root path."""
    if project_root is not None:
        return Path(project_root).resolve()

    root_str = os.environ.get("GODOTIQ_PROJECT_ROOT")
    if root_str:
        return Path(root_str).resolve()

    discovered = discover_project_root()
    if discovered is None:
        raise ValueError("Godot project root not found")
    return discovered.resolve()


def _get_config(root: Path, config: GodotIQConfig | None = None) -> GodotIQConfig:
    """Resolve the active project config."""
    if config is not None:
        return config
    return load_config(str(root / ".godotiq.json"))


def _resolve(path: str, root: Path | None = None) -> Path:
    """Resolve a res:// or relative path to an absolute Path within the project root.

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
        raise ValueError(f"Path is outside the project root: {path}")

    return resolved


def _relative_to_root(path: Path, root: Path) -> str:
    """Return the project-relative POSIX path for config matching."""
    try:
        rel = path.relative_to(root)
    except ValueError:
        rel = path
    return rel.as_posix()


def _is_protected(
    path: Path,
    root: Path | None = None,
    config: GodotIQConfig | None = None,
) -> bool:
    """Check if a path matches protected file patterns.

    Uses path relative to project root to avoid false positives when the
    project is located under a directory named 'saves' or '.godot'.
    """
    if root is None:
        root = _get_root()
    return _get_config(root, config).is_file_protected(_relative_to_root(path, root))


def _is_internal_path(path: Path, root: Path) -> bool:
    """Return True when a path points inside GodotIQ internal metadata."""
    rel = _relative_to_root(path, root)
    return rel == ".godotiq" or rel.startswith(".godotiq/")


def _matches_type_filter(filename: str, filter_name: str) -> bool:
    """Check if a filename matches the given type filter."""
    if filter_name == "all":
        return True
    extensions = TYPE_FILTERS.get(filter_name)
    if extensions is None:
        return False
    return Path(filename).suffix.lower() in extensions


async def file_ops(
    op: str = "list",
    path: str = "",
    query: str = "",
    filter: str = "all",
    recursive: bool = False,
    context_lines: int = 2,
    max_depth: int = 3,
    show_sizes: bool = False,
    content: str = "",
    destination: str = "",
    project_root: str | Path | None = None,
    config: GodotIQConfig | None = None,
) -> dict:
    """Execute filesystem operations within the Godot project."""
    try:
        root = _get_root(project_root)
        resolved_config = _get_config(root, config)

        if op == "list":
            return _op_list(path, filter, recursive, root)
        elif op == "read":
            return _op_read(path, root)
        elif op == "write":
            return _op_write(path, content, root, resolved_config)
        elif op == "move":
            return _op_move(path, destination, root, resolved_config)
        elif op == "delete":
            return _op_delete(path, root, resolved_config)
        elif op == "search":
            return _op_search(path, query, filter, context_lines, root)
        elif op == "tree":
            return _op_tree(path, max_depth, show_sizes, root)
        elif op == "uid_to_path":
            return _op_uid_to_path(query, root)
        elif op == "path_to_uid":
            return _op_path_to_uid(path, root)
        elif op == "rename":
            return _op_rename(path, destination, content, root, resolved_config)
        else:
            return {"error": f"Unknown operation: {op}"}
    except ValueError as e:
        return {"error": str(e)}


def _op_list(path: str, type_filter: str, recursive: bool, root: Path) -> dict:
    """List directory entries."""
    if path:
        target = _resolve(path, root)
    else:
        target = root

    if _is_internal_path(target, root):
        return {"error": f"Cannot access internal GodotIQ directory: {path}"}

    if not target.is_dir():
        return {"error": f"Directory not found: {path or '.'}"}

    entries: list[dict] = []

    if recursive:
        for dirpath, dirnames, filenames in os.walk(target):
            # Filter out excluded directories in-place
            dirnames[:] = [d for d in dirnames if d not in EXCLUDED_DIRS]
            for fname in filenames:
                if _matches_type_filter(fname, type_filter):
                    full = Path(dirpath) / fname
                    rel = full.relative_to(root)
                    entries.append({"name": str(rel), "type": "file"})
    else:
        for entry in sorted(target.iterdir()):
            if entry.name in EXCLUDED_DIRS:
                continue
            if entry.is_dir():
                entries.append({"name": entry.name, "type": "dir"})
            elif entry.is_file() and _matches_type_filter(entry.name, type_filter):
                entries.append({"name": entry.name, "type": "file"})

    return {"op": "list", "path": path or ".", "entries": entries}


def _op_read(path: str, root: Path) -> dict:
    """Read a text file."""
    resolved = _resolve(path, root)

    if _is_internal_path(resolved, root):
        return {"error": f"Cannot read internal GodotIQ file: {path}"}

    if not resolved.is_file():
        return {"error": f"File not found: {path}"}

    try:
        text = resolved.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return {"error": f"Cannot read binary file: {path}"}

    line_count = text.count("\n")
    if text and not text.endswith("\n"):
        line_count += 1

    return {
        "op": "read",
        "path": path,
        "content": text,
        "lines": line_count,
        "size": resolved.stat().st_size,
    }


def _op_write(path: str, content: str, root: Path, config: GodotIQConfig) -> dict:
    """Write content to a file."""
    resolved = _resolve(path, root)

    if _is_internal_path(resolved, root):
        return {"error": f"Cannot modify internal GodotIQ file: {path}"}
    if _is_protected(resolved, root, config):
        return {"error": f"Cannot modify protected file: {path}"}

    created = not resolved.exists()
    resolved.parent.mkdir(parents=True, exist_ok=True)
    resolved.write_text(content, encoding="utf-8")

    return {
        "op": "write",
        "path": path,
        "size": resolved.stat().st_size,
        "created": created,
    }


def _op_move(path: str, destination: str, root: Path, config: GodotIQConfig) -> dict:
    """Move/rename a file."""
    resolved_src = _resolve(path, root)
    resolved_dst = _resolve(destination, root)

    if _is_internal_path(resolved_src, root):
        return {"error": f"Cannot modify internal GodotIQ file: {path}"}
    if _is_internal_path(resolved_dst, root):
        return {"error": f"Cannot modify internal GodotIQ file: {destination}"}
    if _is_protected(resolved_src, root, config):
        return {"error": f"Cannot modify protected file: {path}"}
    if _is_protected(resolved_dst, root, config):
        return {"error": f"Cannot modify protected file: {destination}"}

    if not resolved_src.exists():
        return {"error": f"File not found: {path}"}

    resolved_dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(resolved_src), str(resolved_dst))

    return {
        "op": "move",
        "source": path,
        "destination": destination,
        "success": True,
    }


def _op_delete(path: str, root: Path, config: GodotIQConfig) -> dict:
    """Delete a file."""
    resolved = _resolve(path, root)

    if _is_internal_path(resolved, root):
        return {"error": f"Cannot modify internal GodotIQ file: {path}"}
    if _is_protected(resolved, root, config):
        return {"error": f"Cannot modify protected file: {path}"}

    if not resolved.exists():
        return {"error": f"File not found: {path}"}

    resolved.unlink()

    return {"op": "delete", "path": path, "success": True}


def _op_search(path: str, query: str, type_filter: str, context_lines: int, root: Path) -> dict:
    """Search for text across files."""
    if not query:
        return {"error": "Search query is required"}

    if path:
        target = _resolve(path, root)
    else:
        target = root

    if _is_internal_path(target, root):
        return {"error": f"Cannot access internal GodotIQ directory: {path}"}

    matches: list[dict] = []
    capped = False

    for dirpath, dirnames, filenames in os.walk(target):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDED_DIRS]

        for fname in filenames:
            if not _matches_type_filter(fname, type_filter):
                continue

            full = Path(dirpath) / fname
            try:
                text = full.read_text(encoding="utf-8")
            except (UnicodeDecodeError, PermissionError):
                continue

            lines = text.splitlines()
            rel = str(full.relative_to(root))

            for i, line in enumerate(lines):
                if query in line:
                    before = lines[max(0, i - context_lines):i]
                    after = lines[i + 1:i + 1 + context_lines]
                    matches.append({
                        "file": rel,
                        "line": i + 1,
                        "content": line,
                        "context_before": before,
                        "context_after": after,
                    })
                    if len(matches) >= MAX_SEARCH_MATCHES:
                        capped = True
                        break

            if capped:
                break
        if capped:
            break

    return {
        "op": "search",
        "query": query,
        "matches": matches,
        "total_matches": len(matches),
        "capped": capped,
    }


def _op_tree(path: str, max_depth: int, show_sizes: bool, root: Path) -> dict:
    """Build a directory tree structure."""
    if path:
        target = _resolve(path, root)
    else:
        target = root

    if _is_internal_path(target, root):
        return {"error": f"Cannot access internal GodotIQ directory: {path}"}

    def build_tree(dir_path: Path, depth: int) -> dict:
        node: dict = {"name": dir_path.name, "type": "dir"}
        if depth >= max_depth:
            return node

        children: list[dict] = []
        try:
            entries = sorted(dir_path.iterdir(), key=lambda p: (not p.is_dir(), p.name))
        except PermissionError:
            return node

        for entry in entries:
            if entry.name in EXCLUDED_DIRS:
                continue
            if entry.is_dir():
                children.append(build_tree(entry, depth + 1))
            elif entry.is_file():
                child: dict = {"name": entry.name, "type": "file"}
                if show_sizes:
                    child["size"] = entry.stat().st_size
                children.append(child)

        node["children"] = children
        return node

    tree = build_tree(target, 0)

    return {"op": "tree", "path": path or ".", "tree": tree}


def _op_uid_to_path(uid: str, root: Path | None = None) -> dict:
    """Convert a uid:// string to a res:// path by scanning project files."""
    if not uid or not uid.startswith("uid://"):
        return {"error": "Invalid UID format. Expected uid://..."}
    if root is None:
        root = _get_root()

    # Strategy 1: scan .tscn / .tres files for uid references
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDED_DIRS]
        for fname in filenames:
            if not fname.endswith((".tscn", ".tres", ".import")):
                continue
            full = Path(dirpath) / fname
            try:
                text = full.read_text(encoding="utf-8")
            except (UnicodeDecodeError, PermissionError):
                continue
            if uid not in text:
                continue
            # In .import files, extract source_file
            if fname.endswith(".import"):
                for line in text.split("\n"):
                    if line.startswith("source_file="):
                        source = line.split("=", 1)[1].strip().strip('"')
                        return {"op": "uid_to_path", "uid": uid, "path": source}
            # In .tscn/.tres, find path= next to the uid
            for line in text.split("\n"):
                if uid in line and "path=" in line:
                    # Extract path="res://..." from the line
                    idx = line.find('path="')
                    if idx >= 0:
                        start = idx + 6
                        end = line.find('"', start)
                        if end > start:
                            return {"op": "uid_to_path", "uid": uid, "path": line[start:end]}

    return {"op": "uid_to_path", "uid": uid, "path": None, "error": "UID not found in project"}


def _op_path_to_uid(path: str, root: Path | None = None) -> dict:
    """Find UID associated with a res:// path."""
    if not path:
        return {"error": "Path is required"}
    if root is None:
        root = _get_root()
    res_path = path.replace("res://", "") if path.startswith("res://") else path
    full_path = root / res_path

    # Strategy 1: check .uid file next to resource
    uid_file = Path(str(full_path) + ".uid")
    if uid_file.exists():
        try:
            content = uid_file.read_text(encoding="utf-8").strip()
            if content.startswith("uid://"):
                return {"op": "path_to_uid", "path": path, "uid": content}
        except (UnicodeDecodeError, PermissionError):
            pass

    # Strategy 2: scan .tscn/.tres files for path reference with uid
    res_ref = path if path.startswith("res://") else f"res://{path}"
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDED_DIRS]
        for fname in filenames:
            if not fname.endswith((".tscn", ".tres")):
                continue
            full = Path(dirpath) / fname
            try:
                text = full.read_text(encoding="utf-8")
            except (UnicodeDecodeError, PermissionError):
                continue
            if res_ref not in text:
                continue
            for line in text.split("\n"):
                if res_ref in line and "uid://" in line:
                    # Extract uid://... from the line
                    idx = line.find("uid://")
                    if idx >= 0:
                        end = idx + 6
                        while end < len(line) and line[end] not in ('"', " ", "]", ")"):
                            end += 1
                        return {"op": "path_to_uid", "path": path, "uid": line[idx:end]}

    return {"op": "path_to_uid", "path": path, "uid": None, "error": "UID not found"}


_RENAME_SCAN_EXTENSIONS = {".tscn", ".gd", ".tres", ".cfg", ".godot"}


def _op_rename(
    path: str,
    new_path: str,
    update_references_str: str,
    root: Path | None = None,
    config: GodotIQConfig | None = None,
) -> dict:
    """Rename a file and optionally update all references across the project.

    Args:
        path: Old file path (res:// or relative).
        new_path: New file path (passed via 'destination' parameter).
        update_references_str: "true"/"false" (passed via 'content' parameter).
    """
    if not path or not new_path:
        return {"error": "Both 'path' (old) and 'destination' (new) are required for rename"}

    if root is None:
        root = _get_root()
    if config is None:
        config = _get_config(root)

    update_refs = update_references_str.lower() != "false" if update_references_str else True

    old_resolved = _resolve(path, root)
    new_resolved = _resolve(new_path, root)

    if _is_internal_path(old_resolved, root):
        return {"error": f"Cannot rename internal GodotIQ file: {path}"}
    if _is_internal_path(new_resolved, root):
        return {"error": f"Cannot rename to internal GodotIQ path: {new_path}"}
    if _is_protected(old_resolved, root, config):
        return {"error": f"Cannot rename protected file: {path}"}
    if _is_protected(new_resolved, root, config):
        return {"error": f"Cannot rename to protected path: {new_path}"}

    if not old_resolved.exists():
        return {"error": f"File not found: {path}"}

    updated_files: list[str] = []

    if update_refs:
        old_res = path if path.startswith("res://") else f"res://{path}"
        new_res = new_path if new_path.startswith("res://") else f"res://{new_path}"

        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in EXCLUDED_DIRS]
            for fname in filenames:
                if not any(fname.endswith(ext) for ext in _RENAME_SCAN_EXTENSIONS):
                    continue
                full = Path(dirpath) / fname
                try:
                    text = full.read_text(encoding="utf-8")
                except (UnicodeDecodeError, PermissionError):
                    continue
                if old_res in text:
                    new_text = text.replace(old_res, new_res)
                    full.write_text(new_text, encoding="utf-8")
                    updated_files.append(str(full.relative_to(root)))

    # Rename the file
    new_resolved.parent.mkdir(parents=True, exist_ok=True)
    old_resolved.rename(new_resolved)

    # Also rename .uid file if exists
    old_uid = Path(str(old_resolved) + ".uid")
    new_uid = Path(str(new_resolved) + ".uid")
    if old_uid.exists():
        old_uid.rename(new_uid)

    return {
        "op": "rename",
        "old_path": path,
        "new_path": new_path,
        "renamed": True,
        "references_updated": len(updated_files),
        "updated_files": updated_files,
    }
