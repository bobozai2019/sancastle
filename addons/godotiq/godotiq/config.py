"""GodotIQ project configuration loader.

Reads `.godotiq.json` from the project root and provides sensible
defaults when the file is absent.
"""

from __future__ import annotations

import fnmatch
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


_DEFAULT_PROTECTED: list[str] = [
    "project.godot",
    ".godot/**",
    ".godotiq/**",
    "*.import",
    "saves/**",
]

RECEIPT_FILE = "receipt.json"


@dataclass
class GodotIQConfig:
    """GodotIQ project configuration."""

    project: dict[str, Any] = field(default_factory=lambda: {
        "name": "",
        "engine": "godot_4",
        "type": "3d",
    })
    conventions: dict[str, Any] = field(default_factory=dict)
    asset_origins: dict[str, Any] = field(default_factory=dict)
    rooms: dict[str, Any] = field(default_factory=dict)
    protected_files: list[str] = field(default_factory=lambda: list(_DEFAULT_PROTECTED))
    custom_rules: list[dict[str, Any]] = field(default_factory=list)
    token_optimization: dict[str, Any] = field(default_factory=lambda: {
        "default_detail": "normal",
        "enable_diff_cache": True,
        "compact_output": True,
        "max_nodes_per_response": 50,
    })
    disabled_tools: list[str] = field(default_factory=list)
    server: dict[str, Any] = field(default_factory=lambda: {
        "default_detail": "normal",
        "max_nodes_per_response": 200,
        "screenshot_default_scale": 0.25,
    })

    # -- query helpers --

    def is_tool_disabled(self, tool_name: str) -> bool:
        """Check if a tool is disabled by name."""
        return tool_name in self.disabled_tools

    def is_file_protected(self, file_path: str) -> bool:
        """Check if a file matches any protected pattern (fnmatch glob)."""
        for pattern in self.protected_files:
            if fnmatch.fnmatch(file_path, pattern):
                return True
        return False

    def get_default_detail(self) -> str:
        """Return the project's default detail level."""
        return self.server.get("default_detail", "normal")

    def get_asset_scale(self, origin: str) -> list[float] | None:
        """Return default scale for an asset origin, or None."""
        origin_config = self.asset_origins.get(origin, {})
        return origin_config.get("default_scale")


def load_config(path: str | None = None) -> GodotIQConfig:
    """Load GodotIQ configuration from a JSON file.

    When *path* is ``None`` the loader looks for ``.godotiq.json`` in the
    current working directory.  If the file does not exist, default
    configuration values are returned without raising an error.

    Args:
        path: Optional explicit path to the configuration file.

    Returns:
        A populated GodotIQConfig instance.
    """
    config_path = Path(path) if path else Path(".godotiq.json")

    if not config_path.exists():
        return GodotIQConfig()

    try:
        with config_path.open() as f:
            data = json.load(f)
    except (json.JSONDecodeError, IOError):
        return GodotIQConfig()

    defaults = GodotIQConfig()
    return GodotIQConfig(
        project=data.get("project", defaults.project),
        conventions=data.get("conventions", {}),
        asset_origins=data.get("asset_origins", {}),
        rooms=data.get("rooms", {}),
        protected_files=data.get("protected_files", list(_DEFAULT_PROTECTED)),
        custom_rules=data.get("custom_rules", []),
        token_optimization=data.get("token_optimization",
                                     defaults.token_optimization),
        disabled_tools=data.get("disabled_tools", []),
        server=data.get("server", defaults.server),
    )
