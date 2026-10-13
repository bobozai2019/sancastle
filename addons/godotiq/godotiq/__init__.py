"""GodotIQ — The definitive MCP for AI-assisted Godot development."""

from importlib.metadata import PackageNotFoundError, version


def _get_version() -> str:
    """Read version from package metadata (single source of truth: pyproject.toml)."""
    try:
        return version("godotiq")
    except PackageNotFoundError:
        return "0.0.0-dev"


__version__: str = _get_version()
