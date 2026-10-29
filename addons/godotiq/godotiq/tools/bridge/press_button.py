"""godotiq_press_button: Trigger a button's pressed signal in the running game.

Unlike godotiq_input tap (which simulates mouse click and may not reach
buttons inside ScrollContainer), this directly emits the button's pressed
signal. Useful for buttons that are off-screen or inside scroll containers.
"""

from __future__ import annotations

from godotiq.bridge.session import get_bridge

TOOL_NAME = "godotiq_press_button"
TOOL_DESCRIPTION = (
    "Trigger a button's pressed signal in the running game by name. "
    "Unlike godotiq_input tap (mouse simulation), this directly emits "
    "the pressed signal. Works for buttons inside ScrollContainer. "
    "Game must be running."
)


async def press_button(
    name: str = "",
    root: str = "",
    session_id: int | None = None,
    max_visited_nodes: int = 5000,
) -> dict:
    """Trigger a button's pressed signal.

    Args:
        name: Button node name to find and press (e.g. "@Button@44").
        root: Optional root node path to search from.
        max_visited_nodes: Maximum scene nodes inspected (hard-capped game-side).

    Returns:
        Dict with status, name, path, text of the pressed button.
    """
    if not name:
        return {"error": "Missing required parameter: name"}

    bridge = await get_bridge()
    params = {"name": name, "max_visited_nodes": max_visited_nodes}
    if root:
        params["root"] = root
    if session_id is not None:
        params["session_id"] = session_id
    return await bridge.request("press_button", params=params, timeout=10.0)
