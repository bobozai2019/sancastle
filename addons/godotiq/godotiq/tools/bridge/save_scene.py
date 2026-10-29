"""godotiq_save_scene: Save the current scene in the editor.

Closes the editing loop: node_ops modifies -> save_scene persists.
Editor-side — no game needed.
"""

from __future__ import annotations

from godotiq.bridge.session import get_bridge

TOOL_NAME = "godotiq_save_scene"
TOOL_DESCRIPTION = (
    "Save the currently open scene in the Godot editor. "
    "Call after node_ops or other modifications to persist changes to disk. "
    "In-place save only. Editor-side — no game needed."
)


async def save_scene() -> dict:
    """Save the current scene in place.

    Returns:
        Dict with saved (bool), scene_path, scene_name, file_size_kb (int), node_count (int).
    """
    bridge = await get_bridge()
    return await bridge.request("save_scene", params={}, timeout=5.0)
