"""GodotIQ session — unified project state for MCP tools.

Bridges the parsers into a single cached state object. Created once
at server startup, provides all cross-reference queries the tools need.
"""

from __future__ import annotations

import logging
import os
from collections import defaultdict
from pathlib import Path

logger = logging.getLogger(__name__)

from godotiq.cache.file_cache import FileCache
from godotiq.config import load_config, GodotIQConfig
from godotiq.parsers.gd_parser import parse_gd, GdScript
from godotiq.parsers.project_index import scan_project, ProjectIndex
from godotiq.parsers.scene_resolver import (
    resolve_scene,
    calculate_world_transforms,
    ResolvedScene,
    WorldNode,
)
from godotiq.parsers.tscn_parser import parse_tscn, TscnScene


class GodotIQSession:
    """Holds loaded project state. Created once, cached, refreshed on file changes."""

    def __init__(self, project_root: str | Path) -> None:
        self.project_root = Path(project_root)
        self.cache = FileCache()
        self.config: GodotIQConfig = GodotIQConfig()
        self._index: ProjectIndex | None = None
        self._project_godot_mtime: int = -1
        self._gd_scripts: dict[str, GdScript] = {}
        self._gd_script_mtimes: dict[str, float] = {}
        self._tscn_scenes: dict[str, TscnScene] = {}
        self._tscn_scene_mtimes: dict[str, float] = {}
        self._resolved_scenes: dict[str, tuple[ResolvedScene, list[WorldNode]]] = {}

    def load(self) -> None:
        """Full project scan + parse all .gd files with autoload awareness."""
        self._gd_scripts.clear()
        self._gd_script_mtimes.clear()
        self._tscn_scenes.clear()
        self._tscn_scene_mtimes.clear()
        self._resolved_scenes.clear()
        self._index = scan_project(self.project_root, self.cache)
        godot_path = self.project_root / "project.godot"
        self._project_godot_mtime = self._get_mtime(godot_path)
        autoload_names = list(self._index.autoloads.keys())
        for script_path in self._index.scripts:
            abs_path = self._resolve_res_path(script_path)
            if abs_path.exists():
                try:
                    self._gd_scripts[script_path] = parse_gd(
                        str(abs_path), known_autoloads=autoload_names
                    )
                    self._gd_script_mtimes[script_path] = self._get_mtime(abs_path)
                except Exception:
                    logger.warning("Failed to parse %s, skipping", script_path)
        for scene_path, scene in self._index.scenes.items():
            self._tscn_scenes[scene_path] = scene
            self._tscn_scene_mtimes[scene_path] = self._get_mtime(
                self._resolve_res_path(scene_path)
            )
        config_path = self.project_root / ".godotiq.json"
        self.config = load_config(str(config_path))

    def refresh(self) -> None:
        """Reload the full project state after on-disk mutations."""
        self.load()

    @property
    def index(self) -> ProjectIndex | None:
        """Project index with automatic freshness check for project.godot.

        Accessing this property checks whether project.godot has been modified
        since the last load/refresh. If it has, only project_name and autoloads
        are re-read (not the full project rescan).

        Known limitation: scene_count and script_count come from the full
        filesystem scan and are NOT refreshed by this mechanism.
        """
        if self._index is None:
            return None
        if not self._is_project_godot_fresh():
            self._refresh_project_index()
        return self._index

    def _is_project_godot_fresh(self) -> bool:
        """Check if cached project index matches current project.godot on disk."""
        if self._project_godot_mtime == -1:
            return False
        godot_path = self.project_root / "project.godot"
        return self._project_godot_mtime == self._get_mtime(godot_path)

    def _refresh_project_index(self) -> None:
        """Re-read project.godot and update cached index fields.

        Only updates project_name and autoloads (which come from project.godot).
        Does NOT re-parse scripts or scenes (expensive and not needed here).
        """
        from godotiq.parsers.project_index import _parse_project_godot

        godot_path = self.project_root / "project.godot"
        if not godot_path.exists():
            return
        project_name, autoloads = _parse_project_godot(godot_path)
        self._index.project_name = project_name
        self._index.autoloads = autoloads
        self._project_godot_mtime = self._get_mtime(godot_path)

    def _resolve_res_path(self, res_path: str) -> Path:
        """Convert a res:// path to an absolute filesystem path."""
        relative = res_path.removeprefix("res://")
        return self.project_root / relative

    def _get_mtime(self, path: Path) -> int:
        """Return the current mtime in nanoseconds for a project file, or -1."""
        try:
            return path.stat().st_mtime_ns
        except OSError:
            return -1

    def _is_script_cache_fresh(self, res_path: str) -> bool:
        """Check whether a cached script entry still matches the file on disk."""
        if res_path not in self._gd_scripts:
            return False
        if res_path not in self._gd_script_mtimes:
            return True
        abs_path = self._resolve_res_path(res_path)
        if not abs_path.is_file():
            return False
        return self._gd_script_mtimes.get(res_path) == self._get_mtime(abs_path)

    def _is_scene_cache_fresh(self, res_path: str) -> bool:
        """Check whether a cached scene entry still matches the file on disk."""
        if res_path not in self._tscn_scenes:
            return False
        if res_path not in self._tscn_scene_mtimes:
            return True
        abs_path = self._resolve_res_path(res_path)
        if not abs_path.is_file():
            return False
        return self._tscn_scene_mtimes.get(res_path) == self._get_mtime(abs_path)

    def _invalidate_script_cache(self, res_path: str) -> None:
        """Drop cached script data for a res:// path."""
        self._gd_scripts.pop(res_path, None)
        self._gd_script_mtimes.pop(res_path, None)

    def _invalidate_scene_cache(self, res_path: str) -> None:
        """Drop cached scene and resolved spatial data for a res:// path."""
        self._tscn_scenes.pop(res_path, None)
        self._tscn_scene_mtimes.pop(res_path, None)
        self._resolved_scenes.pop(res_path, None)
        if self._index is not None:
            self._index.scenes.pop(res_path, None)

    def _resolve_existing_script_path(self, path: str) -> str | None:
        """Resolve a script path directly from disk, bypassing stale indexes."""
        res_path = self.to_res_path(path)
        relative = res_path.removeprefix("res://")
        if Path(relative).suffix.lower() != ".gd":
            return None

        abs_path = self._resolve_res_path(res_path)
        if not abs_path.is_file():
            return None

        if self._index is not None and res_path not in self._index.scripts:
            self._index.scripts.append(res_path)
            self._index.total_scripts = len(self._index.scripts)
        return res_path

    def get_script(self, res_path: str) -> GdScript | None:
        """Return the parsed GdScript for the given res:// path, or None."""
        normalized_input = self.to_res_path(res_path)
        if self._is_script_cache_fresh(normalized_input):
            return self._gd_scripts[normalized_input]
        if normalized_input in self._gd_scripts:
            self._invalidate_script_cache(normalized_input)

        normalized = self._resolve_existing_script_path(normalized_input)
        if normalized is None:
            return None

        abs_path = self._resolve_res_path(normalized)
        autoload_names = list(self._index.autoloads.keys()) if self._index else []
        try:
            parsed = parse_gd(
                str(abs_path),
                known_autoloads=autoload_names,
            )
        except FileNotFoundError:
            return None

        self._gd_scripts[normalized] = parsed
        self._gd_script_mtimes[normalized] = self._get_mtime(abs_path)
        return parsed

    def get_scene(self, res_path: str) -> TscnScene | None:
        """Lazy parse + cache a .tscn scene."""
        normalized = self.to_res_path(res_path)
        if self._is_scene_cache_fresh(normalized):
            return self._tscn_scenes[normalized]
        if normalized in self._tscn_scenes:
            self._invalidate_scene_cache(normalized)

        abs_path = self._resolve_res_path(normalized)
        if abs_path.exists():
            scene = parse_tscn(str(abs_path))
            self._tscn_scenes[normalized] = scene
            self._tscn_scene_mtimes[normalized] = self._get_mtime(abs_path)
            if self._index is not None:
                self._index.scenes[normalized] = scene
            return scene
        return None

    def resolve_scene_spatial(
        self, res_path: str
    ) -> tuple[ResolvedScene, list[WorldNode]] | None:
        """Lazy resolve + cache scene spatial data."""
        normalized = self.to_res_path(res_path)
        if normalized in self._resolved_scenes and self._is_scene_cache_fresh(normalized):
            return self._resolved_scenes[normalized]
        if normalized in self._resolved_scenes:
            self._resolved_scenes.pop(normalized, None)

        scene = self.get_scene(normalized)
        if scene is None:
            return None
        resolved = resolve_scene(scene, self.project_root)
        world_nodes = calculate_world_transforms(resolved)
        result = (resolved, world_nodes)
        self._resolved_scenes[normalized] = result
        return result

    def get_all_signal_definitions(self) -> dict[str, list[str]]:
        """Map signal names to the scripts that define them."""
        result: dict[str, list[str]] = defaultdict(list)
        for path, gd in self._gd_scripts.items():
            for sig in gd.signals:
                result[sig.name].append(path)
        return dict(result)

    def get_all_signal_emissions(self) -> dict[str, list[str]]:
        """Map signal names to the scripts that emit them."""
        result: dict[str, list[str]] = defaultdict(list)
        for path, gd in self._gd_scripts.items():
            for em in gd.signal_emissions:
                result[em.signal_name].append(path)
        return dict(result)

    def get_all_signal_connections(self) -> dict[str, list[str]]:
        """Map signal source to the scripts that connect to them."""
        result: dict[str, list[str]] = defaultdict(list)
        for path, gd in self._gd_scripts.items():
            for conn in gd.signal_connections:
                result[conn.signal_source].append(path)
        return dict(result)

    def get_autoload_dependents(self, autoload_name: str) -> list[str]:
        """Return list of res:// script paths referencing the given autoload."""
        result: list[str] = []
        for path, gd in self._gd_scripts.items():
            for ref in gd.autoload_refs:
                if ref.autoload_name == autoload_name:
                    result.append(path)
                    break
        return result

    def to_res_path(self, path: str) -> str:
        """Convert a filesystem path to a res:// path."""
        if path.startswith("res://"):
            return path
        p = Path(path)
        if p.is_absolute():
            try:
                relative = p.relative_to(self.project_root)
                return f"res://{relative}"
            except ValueError:
                return f"res://{path}"
        return f"res://{path}"

    def resolve_file_path(self, path: str) -> str | None:
        """Resolve a file identifier to a res:// path if it exists in the project."""
        res_path = self.to_res_path(path)
        direct_script = self._resolve_existing_script_path(res_path)
        if direct_script is not None:
            return direct_script
        if res_path in self._gd_scripts:
            if self._index is None or res_path not in self._index.scripts:
                return res_path
        if self._index is None:
            return None
        if res_path in self._index.scenes:
            return res_path
        if res_path in self._index.assets:
            return res_path
        return None


def discover_project_root() -> Path | None:
    """Discover the Godot project root directory.

    Strategy:
    1. Check GODOTIQ_PROJECT_ROOT env var
    2. Check cwd for .godotiq.json
    3. Walk up from cwd looking for project.godot
    """
    env_root = os.environ.get("GODOTIQ_PROJECT_ROOT")
    if env_root:
        p = Path(env_root)
        if (p / "project.godot").exists():
            return p

    cwd = Path.cwd()
    if (cwd / ".godotiq.json").exists():
        return cwd

    current = cwd
    while current != current.parent:
        if (current / "project.godot").exists():
            return current
        current = current.parent

    return None
