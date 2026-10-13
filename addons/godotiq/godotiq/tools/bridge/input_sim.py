"""A04 — godotiq_input: Simulate user input in the running game.

Supports:
- Action-based input (press/release with hold duration) — GDAI pattern
- Key-based input (physical key presses)
- Semantic UI targeting (tap a button by node name)
- Side-effect tracking (what changed in game state)
- Sequential command execution with waits

One simulation at a time (enforced server-side).
"""

from __future__ import annotations

from godotiq.bridge.session import get_bridge

TOOL_NAME = "godotiq_input"
TOOL_DESCRIPTION = (
    "Simulate user input in the running game. Supports: "
    "action-based (Input actions like 'move_left'), key-based (physical keys), "
    "mouse motion (relative movement for FPS camera), "
    "viewport click (click_at screen coordinates), "
    "world click (click_at_world 3D coordinates via camera projection), "
    "viewport drag (drag_at with timed press/move/release), "
    "and UI targeting (tap buttons by node name). "
    "Commands execute sequentially. Use track_side_effects to see what changed. "
    "Game must be running. One simulation at a time."
)


async def input_sim(
    commands: list[dict] | None = None,
    track_side_effects: bool = False,
    continue_on_error: bool = False,
    wait_for: str = "",
    wait_for_timeout_ms: int = 5000,
    session_id: int | None = None,
) -> dict:
    """Simulate input in the running game.

    Args:
        commands: Sequential list of input commands. Each can be:
            - Action: {"actions": ["move_left", "jump"], "hold_ms": 500}
            - Wait: {"wait_ms": 200}
            - Key: {"key": "space", "hold_ms": 100, "key_mode": "physical"}
              or browser-style aliases like {"key": "ArrowUp"} / {"key": "PageUp"}.
              key_mode is "physical" (default) or "logical". Prefer actions for
              project mappings because they follow the real _input pipeline.
            - UI tap: {"tap": "AcceptButton"}
            - Mouse motion: {"mouse_motion": {"relative_x": 200, "relative_y": 0}}
            - Viewport click: {"click_at": [640, 360]} or {"click_at": [640, 360], "button": "right"}
              Supported buttons: "left" (default), "right", "middle"
            - World click: {"click_at_world": [5.0, 0.0, 3.0]}
              Requires active Camera3D. Converts world coords to screen via camera.unproject_position().
            - Viewport drag: {"drag_at": {"from": [120, 180], "to": [520, 420],
              "hold_before_ms": 100, "duration_ms": 500, "hold_after_ms": 100, "steps": 30}}
              Presses at from, drags to to, then releases. Defaults: 100ms hold before, 500ms move, 100ms hold after.
        track_side_effects: Monitor autoload state changes before/after (default False).
        continue_on_error: Keep going if a command fails (default False).
        wait_for: Optional signal to wait for after all commands execute.
            Format: "signal:NodeName.signal_name" (e.g. "signal:OrderManager.order_accepted").
            Supports signals with zero or one argument. Wider signal signatures
            are rejected explicitly. Commands execute after the listener is connected.
        wait_for_timeout_ms: Timeout for wait_for in milliseconds (default 5000).

    Returns:
        Dict with success, commands_executed, results per command, side_effects,
        signal_received (if wait_for used), signal_data.
    """
    if not commands:
        return {"error": "No commands provided", "success": False}

    params = {
        "commands": commands,
        "track_side_effects": track_side_effects,
        "continue_on_error": continue_on_error,
        "wait_for": wait_for,
        "wait_for_timeout_ms": wait_for_timeout_ms,
    }
    if session_id is not None:
        params["session_id"] = session_id

    bridge = await get_bridge()
    return await bridge.request("input", params=params, timeout=65.0)
