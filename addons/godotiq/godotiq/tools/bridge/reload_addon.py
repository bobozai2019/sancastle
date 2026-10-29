"""godotiq_reload_addon: Hot-reload all GodotIQ addon scripts.

Reloads godotiq_server.gd and godotiq_runtime.gd to pick up new tools
and capabilities without disabling/re-enabling the plugin.
"""

from __future__ import annotations

from godotiq.bridge.session import get_bridge

TOOL_NAME = "godotiq_reload_addon"
TOOL_DESCRIPTION = (
    "Hot-reload all GodotIQ addon scripts to pick up new tools/capabilities. "
    "Use after modifying addon GDScript files. No plugin disable/enable needed."
)


async def reload_addon() -> dict:
    """Reload all addon scripts.

    Returns:
        Dict with reloaded status and per-script results.
    """
    bridge = await get_bridge()
    return await bridge.request("reload_addon", params={}, timeout=10.0)
