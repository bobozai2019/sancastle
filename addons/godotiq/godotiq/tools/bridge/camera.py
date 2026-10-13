"""godotiq_camera: Editor 3D camera control.

Read camera position, temporarily reposition, or focus on a node.
Editor-side — no game needed.
"""

from __future__ import annotations

from godotiq.bridge.session import get_bridge

TOOL_NAME = "godotiq_camera"
TOOL_DESCRIPTION = (
    "Control the editor's 3D camera. "
    "Actions: get_position (read camera state), look_at (reposition camera), "
    "focus_node (select node in editor). "
    "For visual debugging: use godotiq_screenshot(viewport='editor', camera_position=[x,y,z]) "
    "which atomically moves camera + captures + restores. "
    "Editor-side — no game needed."
)


async def camera(
    action: str = "get_position",
    position: list[float] | None = None,
    target: list[float] | None = None,
    node: str = "",
) -> dict:
    """Control the editor camera.

    Args:
        action: "get_position", "look_at", or "focus_node".
        position: [x, y, z] for "look_at" — where to place the camera.
        target: [x, y, z] for "look_at" — where the camera points.
        node: Node name for "focus_node" — selects the node in the editor.

    Returns:
        Dict with action result: position, rotation, node info, etc.
    """
    params: dict = {"action": action}

    if action == "look_at":
        if not position:
            return {"error": "'look_at' requires 'position' [x, y, z]"}
        if len(position) != 3:
            return {"error": "'position' must have exactly 3 elements [x, y, z]"}
        params["position"] = position
        if target:
            if len(target) != 3:
                return {"error": "'target' must have exactly 3 elements [x, y, z]"}
            params["target"] = target

    elif action == "focus_node":
        if not node:
            return {"error": "'focus_node' requires 'node' name"}
        params["node"] = node

    bridge = await get_bridge()
    return await bridge.request("camera", params=params, timeout=5.0)
