"""Run tool — start or stop the Godot game from the editor."""

from __future__ import annotations

import os
from pathlib import Path

from godotiq.bridge.session import get_bridge


def _compute_timeout(explicit_timeout: float, project_root: str | Path | None = None) -> float:
    """Compute scene launch timeout based on project asset count.

    If explicit_timeout > 0, return it directly.
    Otherwise, count .glb files under GODOTIQ_PROJECT_ROOT:
      >100 GLB → 20.0s
      >50  GLB → 15.0s
      else     → 10.0s
    If GODOTIQ_PROJECT_ROOT is not set → 15.0s default.
    """
    if explicit_timeout > 0:
        return explicit_timeout

    root = str(project_root) if project_root is not None else os.environ.get("GODOTIQ_PROJECT_ROOT")
    if not root:
        return 15.0

    try:
        glb_count = sum(1 for _ in Path(root).rglob("*.glb"))
    except Exception:
        return 15.0

    if glb_count > 100:
        return 20.0
    if glb_count > 50:
        return 15.0
    return 10.0


async def run(
    action: str = "play",
    scene: str = "main",
    timeout: float = 0,
    project_root: str | Path | None = None,
    instances: int = 1,
    main_args: str | None = None,
    instance_args: list[str] | None = None,
    main_features: str | None = None,
    instance_features: list[str] | None = None,
    instance_arg_mode: str = "override",
    instance_feature_mode: str = "override",
) -> dict:
    """Start or stop the Godot game from the editor.

    Args:
        action: "play" to start, "stop" to halt the running game.
        scene: Which scene to run — "main", "current", or a res:// path.
            Only used with action="play".
        timeout: Timeout in seconds. 0 means auto-detect from GLB count.
        instances: Number of debug instances to start. 1 forces single-instance
            mode. Values >1 start that many debug instances.

    Returns:
        Dict with action, success, scene, waited_seconds from bridge.
        If no main_scene is configured in project.godot and a specific scene
        was requested, the response includes ``main_scene_empty: true``
        and a ``hint`` field suggesting the caller use set_main_scene.
    """
    bridge = await get_bridge()

    if action == "stop":
        await bridge.request("stop")
        return {"action": "stop"}

    computed_timeout = _compute_timeout(timeout, project_root)
    params: dict = {
        "scene": scene,
        "timeout": computed_timeout,
        "instances": instances,
        "instance_arg_mode": instance_arg_mode,
        "instance_feature_mode": instance_feature_mode,
    }
    if main_args is not None:
        params["main_args"] = main_args
    if instance_args is not None:
        params["instance_args"] = instance_args
    if main_features is not None:
        params["main_features"] = main_features
    if instance_features is not None:
        params["instance_features"] = instance_features
    result = await bridge.request(
        "run",
        params=params,
        timeout=computed_timeout + 5,
    )
    return result
