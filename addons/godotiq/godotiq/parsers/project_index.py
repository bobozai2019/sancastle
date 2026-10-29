"""Project index for Godot project scanning and cross-referencing.

Scans a Godot project directory, parses all .tscn files, and builds
cross-reference maps for scenes, scripts, and assets.
"""

from __future__ import annotations

import logging
import os
import time
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

from godotiq.cache.file_cache import FileCache
from godotiq.parsers.tscn_parser import TscnScene, parse_tscn

logger = logging.getLogger(__name__)

# Extension -> asset type mapping
_ASSET_EXTENSIONS: dict[str, str] = {
    ".glb": "model",
    ".gltf": "model",
    ".obj": "model",
    ".fbx": "model",
    ".png": "texture",
    ".jpg": "texture",
    ".jpeg": "texture",
    ".svg": "texture",
    ".webp": "texture",
    ".ttf": "font",
    ".otf": "font",
    ".woff": "font",
    ".tscn": "scene",
    ".scn": "scene",
    ".tres": "resource",
    ".res": "resource",
    ".gdshader": "shader",
    ".shader": "shader",
    ".wav": "audio",
    ".ogg": "audio",
    ".mp3": "audio",
}


@dataclass
class ProjectIndex:
    """Complete index of a Godot project's files and cross-references."""

    project_root: Path
    project_name: str
    scenes: dict[str, TscnScene]
    scripts: list[str]
    assets: dict[str, dict]
    scene_instances: dict[str, list[str]]
    scene_instance_of: dict[str, list[str]]
    script_to_scenes: dict[str, list[str]]
    resource_usage: dict[str, list[str]]
    autoloads: dict[str, str]
    total_scenes: int
    total_scripts: int
    total_assets: int
    scan_time_ms: float


def scan_project(
    project_root: Path,
    cache: FileCache | None = None,
) -> ProjectIndex:
    """Scan a Godot project directory and build a complete cross-reference index.

    Args:
        project_root: Path to directory containing project.godot.
        cache: Optional FileCache for caching parsed .tscn files.

    Returns:
        ProjectIndex with all scenes parsed and cross-references built.

    Raises:
        FileNotFoundError: If project_root does not exist or has no project.godot.
    """
    project_root = Path(project_root)

    if not project_root.exists():
        raise FileNotFoundError(f"Project root does not exist: {project_root}")

    godot_file = project_root / "project.godot"
    if not godot_file.exists():
        raise FileNotFoundError(f"No project.godot found in {project_root}")

    start = time.monotonic()

    # Walk filesystem
    tscn_files: list[Path] = []
    script_paths: list[str] = []
    assets: dict[str, dict] = {}

    def register_asset(fpath: Path, ext: str) -> None:
        res_path = _to_res_path(fpath, project_root)
        try:
            size = os.path.getsize(fpath)
        except OSError:
            size = 0
        assets[res_path] = {
            "type": _ASSET_EXTENSIONS[ext],
            "size_bytes": size,
            "used_by": [],
        }

    for dirpath, dirnames, filenames in os.walk(project_root):
        current_dir = Path(dirpath)
        dirnames[:] = [
            d for d in dirnames
            if not d.startswith(".")
            and (current_dir / d).relative_to(project_root).as_posix() != "addons/godotiq"
        ]

        for fname in filenames:
            fpath = Path(dirpath) / fname
            ext = fpath.suffix.lower()

            if ext == ".tscn":
                tscn_files.append(fpath)
                register_asset(fpath, ext)
            elif ext == ".gd":
                script_paths.append(_to_res_path(fpath, project_root))
            elif ext in _ASSET_EXTENSIONS:
                register_asset(fpath, ext)

    # Parse .tscn files
    scenes: dict[str, TscnScene] = {}
    for fpath in tscn_files:
        fs_key = str(fpath)
        res_path = _to_res_path(fpath, project_root)

        if cache is not None:
            cached = cache.get(fs_key)
            if cached is not None:
                scenes[res_path] = cached
                continue

        try:
            parsed = parse_tscn(fs_key)
        except Exception:
            logger.warning("Failed to parse %s, skipping", fs_key)
            continue

        scenes[res_path] = parsed
        if cache is not None:
            cache.put(fs_key, parsed)

    # Build cross-reference maps
    scene_instances: dict[str, list[str]] = defaultdict(list)
    scene_instance_of: dict[str, list[str]] = defaultdict(list)
    script_to_scenes: dict[str, list[str]] = defaultdict(list)
    resource_usage: dict[str, list[str]] = defaultdict(list)

    for scene_res, scene_obj in scenes.items():
        for ext in scene_obj.ext_resources.values():
            resource_usage[ext.path].append(scene_res)

            if ext.type == "PackedScene" and ext.path.endswith(".tscn"):
                scene_instances[scene_res].append(ext.path)
                scene_instance_of[ext.path].append(scene_res)

            if ext.type == "Script":
                script_to_scenes[ext.path].append(scene_res)

    # Populate asset used_by
    for asset_path in assets:
        assets[asset_path]["used_by"] = resource_usage.get(asset_path, [])

    # Parse project.godot
    project_name, autoloads = _parse_project_godot(godot_file)

    elapsed_ms = (time.monotonic() - start) * 1000

    return ProjectIndex(
        project_root=project_root,
        project_name=project_name,
        scenes=dict(scenes),
        scripts=script_paths,
        assets=assets,
        scene_instances=dict(scene_instances),
        scene_instance_of=dict(scene_instance_of),
        script_to_scenes=dict(script_to_scenes),
        resource_usage=dict(resource_usage),
        autoloads=autoloads,
        total_scenes=len(scenes),
        total_scripts=len(script_paths),
        total_assets=len(assets),
        scan_time_ms=elapsed_ms,
    )


def rescan_changed(
    previous_index: ProjectIndex,
    cache: FileCache,
) -> ProjectIndex:
    """Perform an incremental rescan, re-parsing only changed files.

    Args:
        previous_index: The previous ProjectIndex to update from.
        cache: FileCache used during the previous scan.

    Returns:
        A new ProjectIndex with updated data.
    """
    return scan_project(previous_index.project_root, cache)


def find_asset_usage(index: ProjectIndex, asset_path: str) -> list[str]:
    """Return list of scene res:// paths that reference the given asset."""
    return index.resource_usage.get(asset_path, [])


def find_unused_assets(index: ProjectIndex) -> list[str]:
    """Return asset res:// paths that are not referenced by any scene."""
    return [
        path for path in index.assets
        if not index.resource_usage.get(path, [])
    ]


def get_scene_dependency_chain(index: ProjectIndex, scene_path: str) -> list[str]:
    """Return all scenes transitively instanced by the given scene (BFS)."""
    visited: set[str] = set()
    queue = list(index.scene_instances.get(scene_path, []))
    result: list[str] = []

    while queue:
        current = queue.pop(0)
        if current in visited:
            continue
        visited.add(current)
        result.append(current)
        for dep in index.scene_instances.get(current, []):
            if dep not in visited:
                queue.append(dep)

    return result


def _to_res_path(abs_path: Path, project_root: Path) -> str:
    """Convert an absolute filesystem path to a res:// path."""
    return "res://" + abs_path.relative_to(project_root).as_posix()


def _parse_project_godot(path: Path) -> tuple[str, dict[str, str]]:
    """Parse project.godot for project name and autoloads.

    Args:
        path: Filesystem path to project.godot.

    Returns:
        Tuple of (project_name, autoloads_dict).

    Raises:
        FileNotFoundError: If the file does not exist.
    """
    if not path.exists():
        raise FileNotFoundError(f"project.godot not found: {path}")

    project_name = ""
    autoloads: dict[str, str] = {}
    current_section = ""

    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()

            if not line or line.startswith(";"):
                continue

            if line.startswith("[") and line.endswith("]"):
                current_section = line[1:-1]
                continue

            if current_section == "application":
                if line.startswith("config/name="):
                    value = line.split("=", 1)[1].strip()
                    if value.startswith('"') and value.endswith('"'):
                        value = value[1:-1]
                    project_name = value

            elif current_section == "autoload":
                if "=" in line:
                    key, value = line.split("=", 1)
                    key = key.strip()
                    value = value.strip()
                    if value.startswith('"') and value.endswith('"'):
                        value = value[1:-1]
                    if value.startswith("*"):
                        value = value[1:]
                    autoloads[key] = value

    return project_name, autoloads
