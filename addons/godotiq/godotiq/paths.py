"""Cross-platform path management for GodotIQ.

Uses platformdirs to provide OS-appropriate directories for license state,
bundle cache, and configuration. All path functions ensure parent directories
exist before returning.
"""

from __future__ import annotations

from pathlib import Path

import platformdirs

from godotiq import config

_dirs = platformdirs.PlatformDirs("GodotIQ", "GodotIQ")


def license_state_dir() -> Path:
    """Return the directory for persistent license state."""
    path = _dirs.user_data_path
    path.mkdir(parents=True, exist_ok=True)
    return path


def bundle_cache_dir() -> Path:
    """Return the directory for downloaded Pro bundles."""
    path = _dirs.user_cache_path / "bundles"
    path.mkdir(parents=True, exist_ok=True)
    return path


def license_cache_path() -> Path:
    """Return the full path to the license cache JSON file."""
    return license_state_dir() / "license_cache.json"


def receipt_path() -> Path:
    """Return the full path to the signed receipt envelope file."""
    return license_state_dir() / config.RECEIPT_FILE


def install_id_path() -> Path:
    """Return the full path to the per-install uuid file."""
    return license_state_dir() / "install_id"


def high_water_mark_path() -> Path:
    """Return the full path to the monotonic high-water mark file."""
    return license_state_dir() / "receipt_hwm"
