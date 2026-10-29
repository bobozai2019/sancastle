"""Bridge tools — MCP wrappers for runtime communication with the Godot addon."""

from __future__ import annotations

from mcp.server.fastmcp import Context

from godotiq.server import mcp
from godotiq.bridge.connection import BridgeConnectionError, BridgeTimeoutError, BridgeError
from godotiq.tool_runtime import guard_tool, get_session_from_ctx, refresh_session

from godotiq.tools.bridge.screenshot import screenshot as _screenshot
from godotiq.tools.bridge.run import run as _run
from godotiq.tools.bridge.perf_snapshot import perf_snapshot as _perf_snapshot
from godotiq.tools.bridge.editor_context import editor_context as _editor_context
from godotiq.tools.bridge.scene_tree import scene_tree as _scene_tree
from godotiq.tools.bridge.node_ops import node_ops as _node_ops
from godotiq.tools.bridge.script_ops import script_ops as _script_ops
from godotiq.tools.bridge.file_ops import file_ops as _file_ops
from godotiq.tools.bridge.input_sim import input_sim as _input_sim
from godotiq.tools.bridge.exec_code import exec_code as _exec_code
from godotiq.tools.bridge.state_inspect import state_inspect as _state_inspect
from godotiq.tools.bridge.nav_query import nav_query as _nav_query
from godotiq.tools.bridge.watch import watch as _watch
from godotiq.tools.bridge.undo_history import undo_history as _undo_history
from godotiq.tools.bridge.save_scene import save_scene as _save_scene
from godotiq.tools.bridge.camera import camera as _camera
from godotiq.tools.bridge.ui_map import ui_map as _ui_map
from godotiq.tools.bridge.build_scene import build_scene as _build_scene
from godotiq.tools.bridge.check_errors import check_errors as _check_errors
from godotiq.tools.bridge.debug_console import read_debug_console as _read_debug_console
from godotiq.tools.bridge.verify_project import verify_project_runs as _verify_project_runs
from godotiq.tools.bridge.verify_motion import verify_motion as _verify_motion
from godotiq.tools.bridge.game_scene_tree import game_scene_tree as _game_scene_tree
from godotiq.tools.bridge.press_button import press_button as _press_button
from godotiq.tools.bridge.find_node import find_node as _find_node
from godotiq.tools.bridge.reload_addon import reload_addon as _reload_addon
from godotiq.tools.output_limit import apply_output_limit, _CHAR_LIMITS
from godotiq.license import pro_unavailable_response
from godotiq.pro_loader import get_pro_implementation

# Import-safe GLB bounds extractor for auto-spacing (Section 8)
try:
    from godotiq.parsers.glb_parser import extract_glb_bounds as _extract_glb_bounds
except Exception:
    _extract_glb_bounds = None


def _resolve_auto_spacing(grid: dict, ctx: Context | None) -> dict | None:
    """Resolve grid spacing from tile_size parameter or GLB bounds.

    Mutates grid["spacing"] in-place if auto-spacing is determined.
    Only called when grid has no explicit "spacing" key.

    Priority: tile_size > GLB auto-detect > default (no mutation).

    Returns:
        Auto-spacing metadata dict {"value": float, "source": str} or None.
    """
    # Priority 1: tile_size parameter
    tile_size = grid.get("tile_size")
    if tile_size is not None:
        if not isinstance(tile_size, (int, float)) or tile_size <= 0:
            return None
        grid["spacing"] = tile_size
        return {"value": tile_size, "source": "tile_size parameter"}

    # Priority 2: GLB auto-detect
    scene_path = grid.get("scene", "")
    if not scene_path.lower().endswith((".glb", ".gltf")):
        return None

    if _extract_glb_bounds is None:
        return None

    session = get_session_from_ctx(ctx)
    if session is None:
        return None

    try:
        abs_path = session._resolve_res_path(scene_path)
        bounds = _extract_glb_bounds(str(abs_path))
    except Exception:
        return None

    if bounds is None or "size" not in bounds:
        return None

    spacing = max(bounds["size"][0], bounds["size"][2])
    if spacing <= 0:
        return None

    grid["spacing"] = spacing
    return {"value": spacing, "source": "GLB bounds"}


@mcp.tool(
    name="godotiq_screenshot",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": True,
    },
)
@guard_tool("godotiq_screenshot", configure_bridge=True)
async def godotiq_screenshot(
    viewport: str = "game",
    scale: float = 0.25,
    format: str = "webp",
    quality: float = 0.5,
    camera_position: list[float] | None = None,
    camera_target: list[float] | None = None,
    region: list[float] | None = None,
    session_id: int | None = None,
    detail: str = "full",
    ctx: Context = None,
) -> dict:
    """Expensive visual-only viewport capture. Use ONLY when visual inspection is required and text tools are insufficient. Prefer state_inspect for values, scene_tree/ui_map for structure, check_errors and _editor_state.recent_errors for failures. Use scale=0.25, quality=0.3 for token-efficient checks.

    Args:
        viewport: "game" (requires running game) or "editor" (3D editor, no game needed).
        scale: Image scale (0.0-1.0). Default 0.25 for token efficiency.
        format: "webp" (default, smallest), "png", "jpg".
        quality: Encoding quality (0.1-1.0). Use 0.3 for routine checks, 0.8 for detail.
        camera_position: [x, y, z] — Editor only. Move camera before capture.
        camera_target: [x, y, z] — Editor only. Camera looks at this point.
        region: [x, y, width, height] — Crop to this pixel region before encoding. Zoom into specific areas without increasing total response size.
        detail: Output verbosity — "brief" (summary), "normal" (default), or "full" (everything).
    """
    try:
        return await _screenshot(
            viewport=viewport, scale=scale, format=format, quality=quality,
            camera_position=camera_position, camera_target=camera_target,
            region=region, session_id=session_id,
        )
    except BridgeConnectionError as e:
        return {"error": str(e), "hint": "Enable the GodotIQ addon in Godot editor and ensure it is running."}
    except BridgeTimeoutError as e:
        return {"error": str(e), "hint": "The game may not be running or the operation timed out."}
    except BridgeError as e:
        return {"error": f"[{e.code}] {e.error_message}"}
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


@mcp.tool(
    name="godotiq_run",
    annotations={
        "readOnlyHint": False,
        "destructiveHint": True,
        "idempotentHint": False,
        "openWorldHint": True,
    },
)
@guard_tool("godotiq_run", configure_bridge=True)
async def godotiq_run(
    action: str = "play",
    scene: str = "main",
    instances: int = 1,
    main_args: str | None = None,
    instance_args: list[str] | None = None,
    main_features: str | None = None,
    instance_features: list[str] | None = None,
    instance_arg_mode: str = "override",
    instance_feature_mode: str = "override",
    detail: str = "full",
    ctx: Context = None,
) -> dict:
    """Start or stop the Godot game. Must call play before using any game-side tools (state_inspect, screenshot, input, nav_query, watch, ui_map). Waits for confirmed startup.

    Args:
        action: "play" to start, "stop" to halt the running game.
        scene: "main" (default), "current", or a res:// path.
        instances: Number of debug instances to start (1..20).
        main_args: Optional launch args for the main instance.
        instance_args: Optional launch args for additional instances.
        main_features: Optional custom feature tags for the main instance.
        instance_features: Optional custom feature tags for additional instances.
        instance_arg_mode: Additional-instance arg mode. v1 supports "override" only.
        instance_feature_mode: Additional-instance feature mode. v1 supports "override" only.
        detail: Output verbosity — "brief" (summary), "normal" (default), or "full" (everything).
    """
    try:
        session = get_session_from_ctx(ctx)
        project_root = session.project_root if session is not None else None
        return await _run(
            action=action,
            scene=scene,
            project_root=project_root,
            instances=instances,
            main_args=main_args,
            instance_args=instance_args,
            main_features=main_features,
            instance_features=instance_features,
            instance_arg_mode=instance_arg_mode,
            instance_feature_mode=instance_feature_mode,
        )
    except BridgeConnectionError as e:
        return {"error": str(e), "hint": "Enable the GodotIQ addon in Godot editor and ensure it is running."}
    except BridgeTimeoutError as e:
        return {"error": str(e), "hint": "The game may not be running or the operation timed out."}
    except BridgeError as e:
        return {"error": f"[{e.code}] {e.error_message}"}
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


@mcp.tool(
    name="godotiq_perf_snapshot",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": True,
    },
)
@guard_tool("godotiq_perf_snapshot", configure_bridge=True)
async def godotiq_perf_snapshot(
    detail: str = "full",
    session_id: int | None = None,
    ctx: Context = None,
) -> dict:
    """FPS, draw calls, memory, node count from the running game. Use for performance profiling. Game must be running.

    Args:
        detail: "brief" (fps + draw_calls only), "normal" (all metrics), "full".
    """
    try:
        return await _perf_snapshot(detail=detail, session_id=session_id)
    except BridgeConnectionError as e:
        return {"error": str(e), "hint": "Enable the GodotIQ addon in Godot editor and ensure it is running."}
    except BridgeTimeoutError as e:
        return {"error": str(e), "hint": "The game may not be running or the operation timed out."}
    except BridgeError as e:
        return {"error": f"[{e.code}] {e.error_message}"}
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


@mcp.tool(
    name="godotiq_editor_context",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": True,
    },
)
@guard_tool("godotiq_editor_context", configure_bridge=True)
async def godotiq_editor_context(detail: str = "normal", ctx: Context = None) -> dict:
    """Call FIRST alongside project_summary. Returns editor state: open scenes, selected nodes, is game running, project path. Essential for understanding current context before any operations.

    Args:
        detail: Output verbosity — "brief" (summary), "normal" (default), or "full" (everything).
    """
    try:
        session = get_session_from_ctx(ctx)
        project_path = str(session.project_root) if session is not None else ""
        result = await _editor_context(project_path=project_path)
        return apply_output_limit(result, detail)
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


@mcp.tool(
    name="godotiq_scene_tree",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": True,
    },
)
@guard_tool("godotiq_scene_tree", configure_bridge=True)
async def godotiq_scene_tree(
    root: str = "",
    depth: int = 3,
    filter_type: str = "",
    include: list[str] | None = None,
    detail: str = "full",
    ctx: Context = None,
) -> dict:
    """Live editor scene tree — actual state with transforms, scripts, groups, visibility. Unlike scene_map (reads .tscn from disk), this reads the editor's live state. Call BEFORE node_ops to see current node names and paths.

    Args:
        root: Node path to start from (e.g. "Level/Enemies"). Empty = scene root.
        depth: Max tree depth (1-10, default 3).
        filter_type: Only include nodes of this type (e.g. "MeshInstance3D").
        include: Data fields per node. Default: ["transform","script","groups","visibility"].
        detail: "brief" (names + types, max 20 nodes), "normal" (default), "full" (+ script paths, signals).
    """
    try:
        return await _scene_tree(root=root, depth=depth, filter_type=filter_type, include=include, detail=detail)
    except BridgeConnectionError as e:
        return {"error": str(e), "hint": "Enable the GodotIQ addon in Godot editor and ensure it is running."}
    except BridgeTimeoutError as e:
        return {"error": str(e), "hint": "The editor may not be responding or the scene is too large."}
    except BridgeError as e:
        return {"error": f"[{e.code}] {e.error_message}"}
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


@mcp.tool(
    name="godotiq_node_ops",
    annotations={
        "readOnlyHint": False,
        "destructiveHint": True,
        "idempotentHint": False,
        "openWorldHint": True,
    },
)
@guard_tool("godotiq_node_ops", configure_bridge=True)
async def godotiq_node_ops(
    operations: list[dict] | None = None,
    scene: str | None = None,
    detail: str = "full",
    ctx: Context = None,
) -> dict:
    """Core scene editing tool. Batch operations with Ctrl+Z undo: move, rotate, scale, set_property, add_child, delete, duplicate, reparent, rename, get_property. All ops in one call = one undo action. ALWAYS add validate:true for spatial operations (move/scale/add_child) to prevent placing objects inside walls or on top of each other. If ANY validated op is BLOCKED, the entire batch is rejected (atomic).

    Args:
        operations: List of operation dicts, each with 'op' key. Max 50 per call.
        scene: Optional .tscn path for spatial validation (auto-detects main scene if omitted).
        detail: Output verbosity — "brief" (summary), "normal" (default), or "full" (everything).
    """
    try:
        scene_data = None
        ops = operations or []

        # Resolve scene data for validation if any op has validate:true
        if any(op.get("validate") for op in ops):
            scene_resolution = _resolve_scene_data(ctx, scene)
            if not scene_resolution["ok"]:
                return {
                    "status": "BLOCKED",
                    "error": "validation_unavailable",
                    "code": "VALIDATION_UNAVAILABLE",
                    "message": "Spatial validation requested but scene data is unavailable. No changes made.",
                    "reason": scene_resolution["message"],
                    "scene": scene_resolution.get("scene"),
                }
            scene_data = scene_resolution["scene_data"]

        result = await _node_ops(operations=ops, scene_data=scene_data)
        return apply_output_limit(result, detail)
    except BridgeConnectionError as e:
        return {"error": str(e), "hint": "Enable the GodotIQ addon in Godot editor and ensure it is running."}
    except BridgeTimeoutError as e:
        return {"error": str(e), "hint": "The operation timed out. Try fewer operations per batch."}
    except BridgeError as e:
        return {"error": f"[{e.code}] {e.error_message}"}
    except ValueError as e:
        return {"error": str(e)}
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


def _resolve_scene_data(ctx: Context | None, scene: str | None) -> dict:
    """Resolve scene spatial data for validation with explicit failure details."""
    try:
        session = get_session_from_ctx(ctx)
        if session is None:
            return {"ok": False, "message": "No Godot project session loaded", "scene": None}

        # Determine res:// path
        if scene:
            res_path = session.to_res_path(scene)
        else:
            from godotiq.tools.memory import _read_main_scene
            res_path = _read_main_scene(session)
            if not res_path:
                return {"ok": False, "message": "No scene specified and no main scene found", "scene": None}

        result = session.resolve_scene_spatial(res_path)
        if result is None:
            return {"ok": False, "message": f"Scene not found or could not be resolved: {res_path}", "scene": res_path}

        _, world_nodes = result
        return {
            "ok": True,
            "scene": res_path,
            "scene_data": {"nodes": [
                {
                    "name": wn.node.name,
                    "type": wn.node.type,
                    "position": list(wn.world_position),
                    "scale": list(wn.world_scale),
                    "depth": wn.depth,
                }
                for wn in world_nodes
            ]},
        }
    except Exception as exc:
        return {"ok": False, "message": f"Scene validation setup failed: {exc}", "scene": scene}


@mcp.tool(
    name="godotiq_script_ops",
    annotations={
        "readOnlyHint": False,
        "destructiveHint": True,
        "idempotentHint": False,
        "openWorldHint": False,
    },
)
@guard_tool("godotiq_script_ops", configure_bridge=True)
async def godotiq_script_ops(
    op: str = "read",
    path: str = "",
    content: str = "",
    patches: list[dict] | None = None,
    validate_before_write: bool = True,
    auto_fix: bool = False,
    dry_run: bool = False,
    detail: str = "full",
    ctx: Context = None,
) -> dict:
    """Read, write, or patch GDScript files with convention validation. ALWAYS prefer this over raw file writes for .gd files. Patch mode (find-and-replace) is safest — only changes what you specify.

    Args:
        op: "read", "write", "patch", or "create".
        path: File path (res:// or relative).
        content: File content for write/create.
        patches: List of {search, replace} dicts for patch mode.
        validate_before_write: Run convention checks before writing (default true).
        auto_fix: Auto-fix detected issues.
        dry_run: Validate without writing.
        detail: Output verbosity — "brief" (summary), "normal" (default), or "full" (everything).
    """
    try:
        session = get_session_from_ctx(ctx)
        result = await _script_ops(
            op=op,
            path=path,
            content=content,
            patches=patches,
            validate_before_write=validate_before_write,
            auto_fix=auto_fix,
            dry_run=dry_run,
            project_root=session.project_root if session is not None else None,
            config=session.config if session is not None else None,
        )
        if op in {"write", "patch"} and result.get("written") is True:
            refresh_session(ctx)
        if op == "create" and result.get("created") is True:
            refresh_session(ctx)
        return result
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


@mcp.tool(
    name="godotiq_file_ops",
    annotations={
        "readOnlyHint": False,
        "destructiveHint": True,
        "idempotentHint": False,
        "openWorldHint": False,
    },
)
@guard_tool("godotiq_file_ops", configure_bridge=True)
async def godotiq_file_ops(
    op: str = "list",
    path: str = "",
    query: str = "",
    filter: str = "all",
    recursive: bool = False,
    context_lines: int = 2,
    max_depth: int = 3,
    show_sizes: bool = False,
    content: str = "",
    destination: str = "",
    detail: str = "full",
    ctx: Context = None,
) -> dict:
    """Filesystem operations within the Godot project: list, read, write, move, delete, search, tree, uid_to_path, path_to_uid, rename (with reference updates). Respects protected files from .godotiq.json. For .gd files, prefer script_ops instead.

    Args:
        op: "list", "read", "write", "move", "delete", "search", "tree", "uid_to_path", "path_to_uid", "rename".
        path: Target path (res:// or relative).
        query: Search query (for search) or uid string (for uid_to_path).
        filter: Type filter ("all", "scenes", "scripts", "images", "audio", etc.).
        recursive: Include subdirectories in list.
        context_lines: Context around search matches (default 2).
        max_depth: Tree depth (default 3).
        show_sizes: Include file sizes in tree.
        content: File content for write. For rename: "false" to skip ref updates.
        destination: Destination for move/rename.
        detail: Output verbosity — "brief" (summary), "normal" (default), or "full" (everything).
    """
    try:
        session = get_session_from_ctx(ctx)
        result = await _file_ops(
            op=op,
            path=path,
            query=query,
            filter=filter,
            recursive=recursive,
            context_lines=context_lines,
            max_depth=max_depth,
            show_sizes=show_sizes,
            content=content,
            destination=destination,
            project_root=session.project_root if session is not None else None,
            config=session.config if session is not None else None,
        )
        if op == "write" and "error" not in result:
            refresh_session(ctx)
        elif op in {"move", "delete"} and result.get("success") is True:
            refresh_session(ctx)
        elif op == "rename" and result.get("renamed") is True:
            refresh_session(ctx)
        # Special case: truncate large string content for read ops
        if op == "read" and "content" in result and "error" not in result:
            limit = _CHAR_LIMITS.get(detail, _CHAR_LIMITS["normal"])
            if limit is not None and isinstance(result["content"], str) and len(result["content"]) > limit:
                original_len = len(result["content"])
                result["content"] = result["content"][:max(limit - 200, 0)]
                result["content_truncated"] = True
                result["content_original_chars"] = original_len
        return apply_output_limit(result, detail)
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


@mcp.tool(
    name="godotiq_input",
    annotations={
        "readOnlyHint": False,
        "destructiveHint": True,
        "idempotentHint": False,
        "openWorldHint": True,
    },
)
@guard_tool("godotiq_input", configure_bridge=True)
async def godotiq_input(
    commands: list[dict] | None = None,
    track_side_effects: bool = False,
    continue_on_error: bool = False,
    wait_for: str = "",
    wait_for_timeout_ms: int = 5000,
    session_id: int | None = None,
    detail: str = "full",
    ctx: Context = None,
) -> dict:
    """Simulate player input in the running game: actions, keys, UI taps, waits. Action commands follow the real Node._input pipeline. Raw key commands use key_mode="physical" by default or key_mode="logical" explicitly. Use after ui_map to know what's on screen. Supports signal verification and side-effect tracking. Game must be running.

    Args:
        commands: Sequential list: {"actions": ["move_left"], "hold_ms": 500}, {"wait_ms": 200}, {"key": "space", "key_mode": "physical"}, {"key": "ArrowUp"}, {"tap": "AcceptButton"}, {"drag_at": {"from": [120, 180], "to": [520, 420]}}. Command ok/dispatched means delivery succeeded, not that a business postcondition occurred.
        track_side_effects: Monitor autoload state changes before/after.
        continue_on_error: Keep going if a command fails.
        wait_for: Zero/one-argument signal to wait for (e.g. "signal:OrderManager.order_accepted"). Wider signatures are rejected.
        wait_for_timeout_ms: Timeout for wait_for in ms.
        detail: Output verbosity — "brief" (summary), "normal" (default), or "full" (everything).
    """
    try:
        result = await _input_sim(
            commands=commands,
            track_side_effects=track_side_effects,
            continue_on_error=continue_on_error,
            wait_for=wait_for,
            wait_for_timeout_ms=wait_for_timeout_ms,
            session_id=session_id,
        )
        return apply_output_limit(result, detail)
    except BridgeConnectionError as e:
        return {"error": str(e), "hint": "Enable the GodotIQ addon in Godot editor and ensure it is running."}
    except BridgeTimeoutError as e:
        return {"error": str(e), "hint": "Game may not be running or input simulation timed out."}
    except BridgeError as e:
        return {"error": f"[{e.code}] {e.error_message}"}
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


@mcp.tool(
    name="godotiq_exec",
    annotations={
        "readOnlyHint": False,
        "destructiveHint": True,
        "idempotentHint": False,
        "openWorldHint": True,
    },
)
@guard_tool("godotiq_exec", configure_bridge=True)
async def godotiq_exec(
    code: str = "",
    context: str = "game",
    timeout_ms: int = 5000,
    session_id: int | None = None,
    detail: str = "full",
    ctx: Context = None,
) -> dict:
    """Execute GDScript code. Last resort — prefer dedicated tools (node_ops, script_ops, state_inspect) over exec. Code MUST contain 'func run():'. In game context use Engine.get_main_loop() instead of get_tree().

    Args:
        code: GDScript with 'func run():'. Return value is stringified.
        context: "game" (sandbox, game must run) or "editor" (full EditorInterface access, no game needed).
        timeout_ms: Bridge response timeout in ms (default 5000). It cannot cancel synchronous GDScript already running.
        detail: Output verbosity — "brief" (summary), "normal" (default), or "full" (everything).
    """
    try:
        return await _exec_code(code=code, context=context, timeout_ms=timeout_ms, session_id=session_id)
    except BridgeConnectionError as e:
        return {"error": str(e), "hint": "Enable the GodotIQ addon in Godot editor and ensure it is running."}
    except BridgeTimeoutError as e:
        return {
            "error": str(e),
            "operation_may_still_be_running": True,
            "hint": "Do not retry automatically. The synchronous Godot operation may still complete later.",
        }
    except BridgeError as e:
        return {"error": f"[{e.code}] {e.error_message}"}
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


@mcp.tool(
    name="godotiq_state_inspect",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": True,
    },
)
@guard_tool("godotiq_state_inspect", configure_bridge=True)
async def godotiq_state_inspect(
    queries: list[dict] | None = None,
    session_id: int | None = None,
    detail: str = "full",
    ctx: Context = None,
) -> dict:
    """Query runtime property values. CHEAPER than screenshots for checking state — use this first. Supports autoload lookup by name, node paths, nested properties, method calls like 'pending_orders.size()'. Game must be running.

    Args:
        queries: [{node: "/root/Main/Player", properties: ["health", "position"]}] or [{autoload: "EconomyManager", properties: ["balance"]}].
        detail: "brief" (values only, no metadata), "normal" (default), "full" (+ class name, node path).
    """
    try:
        return await _state_inspect(queries=queries, detail=detail, session_id=session_id)
    except BridgeConnectionError as e:
        return {"error": str(e), "hint": "Enable the GodotIQ addon in Godot editor and ensure it is running."}
    except BridgeTimeoutError as e:
        return {"error": str(e), "hint": "Game may not be running or query timed out."}
    except BridgeError as e:
        return {"error": f"[{e.code}] {e.error_message}"}
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


@mcp.tool(
    name="godotiq_nav_query",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": True,
    },
)
@guard_tool("godotiq_nav_query", configure_bridge=True)
async def godotiq_nav_query(
    from_node: str = "",
    to_node: str = "",
    from_position: list[float] | None = None,
    to_position: list[float] | None = None,
    optimize: bool = True,
    session_id: int | None = None,
    detail: str = "full",
    ctx: Context = None,
) -> dict:
    """Live pathfinding via NavigationServer3D. "Can A reach B?" Returns path, distance, reachability, navmesh status. Game must be running.

    Args:
        from_node: Source node name (uses its global_position).
        to_node: Target node name.
        from_position: [x, y, z] alternative to from_node.
        to_position: [x, y, z] alternative to to_node.
        optimize: Optimize path (default true).
        detail: "brief" (reachable + distance only), "normal" (+ path points), "full".
    """
    try:
        return await _nav_query(
            from_node=from_node,
            to_node=to_node,
            from_position=from_position,
            to_position=to_position,
            optimize=optimize,
            session_id=session_id,
            detail=detail,
        )
    except BridgeConnectionError as e:
        return {"error": str(e), "hint": "Enable the GodotIQ addon in Godot editor and ensure it is running."}
    except BridgeTimeoutError as e:
        return {"error": str(e), "hint": "Game may not be running or the operation timed out."}
    except BridgeError as e:
        return {"error": f"[{e.code}] {e.error_message}"}
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


@mcp.tool(
    name="godotiq_watch",
    annotations={
        "readOnlyHint": False,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": True,
    },
)
@guard_tool("godotiq_watch", configure_bridge=True)
async def godotiq_watch(
    action: str = "read",
    watches: list[dict] | None = None,
    sample_interval_ms: int = 500,
    session_id: int | None = None,
    detail: str = "full",
    ctx: Context = None,
) -> dict:
    """Persistent property monitoring. Start watching, then read accumulated changes over time. Use for tracking values across game interactions. Game must be running.

    Args:
        action: "start", "stop", "read", "clear".
        watches: For "start": [{node: "/root/Main/Player", properties: ["health", "position"]}].
        sample_interval_ms: Sampling interval (default 500, min 50).
        detail: "brief" (last 10 events only), "normal" (default), "full" (all events + timestamps).
    """
    try:
        result = await _watch(
            action=action,
            watches=watches,
            sample_interval_ms=sample_interval_ms,
            session_id=session_id,
            detail=detail,
        )
        return apply_output_limit(result, detail)
    except BridgeConnectionError as e:
        return {"error": str(e), "hint": "Enable the GodotIQ addon in Godot editor and ensure it is running."}
    except BridgeTimeoutError as e:
        return {"error": str(e), "hint": "Game may not be running or the operation timed out."}
    except BridgeError as e:
        return {"error": f"[{e.code}] {e.error_message}"}
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


@mcp.tool(
    name="godotiq_undo_history",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": True,
    },
)
@guard_tool("godotiq_undo_history", configure_bridge=True)
async def godotiq_undo_history(detail: str = "normal", ctx: Context = None) -> dict:
    """Review what was changed. Shows undo/redo state and recent GodotIQ action history. Call after node_ops to verify changes. Editor-side — no game needed.

    Args:
        detail: Output verbosity — "brief" (summary), "normal" (default), or "full" (everything).
    """
    try:
        result = await _undo_history()
        return apply_output_limit(result, detail)
    except BridgeConnectionError as e:
        return {"error": str(e), "hint": "Enable the GodotIQ addon in Godot editor and ensure it is running."}
    except BridgeTimeoutError as e:
        return {"error": str(e), "hint": "The operation timed out."}
    except BridgeError as e:
        return {"error": f"[{e.code}] {e.error_message}"}
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


@mcp.tool(
    name="godotiq_save_scene",
    annotations={
        "readOnlyHint": False,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    },
)
@guard_tool("godotiq_save_scene", configure_bridge=True)
async def godotiq_save_scene(detail: str = "normal", ctx: Context = None) -> dict:
    """Persist editor changes to disk. Call after node_ops or any scene modifications. In-place save. Editor-side — no game needed.

    Args:
        detail: Output verbosity — "brief" (summary), "normal" (default), or "full" (everything).
    """
    try:
        result = await _save_scene()
        if result.get("saved") is True:
            refresh_session(ctx)
        return result
    except BridgeConnectionError as e:
        return {"error": str(e), "hint": "Enable the GodotIQ addon in Godot editor and ensure it is running."}
    except BridgeTimeoutError as e:
        return {"error": str(e), "hint": "The operation timed out."}
    except BridgeError as e:
        return {"error": f"[{e.code}] {e.error_message}"}
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


@mcp.tool(
    name="godotiq_camera",
    annotations={
        "readOnlyHint": False,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    },
)
@guard_tool("godotiq_camera", configure_bridge=True)
async def godotiq_camera(
    action: str = "get_position",
    position: list[float] | None = None,
    target: list[float] | None = None,
    node: str = "",
    detail: str = "full",
    ctx: Context = None,
) -> dict:
    """Editor 3D camera control: get current position, reposition, or focus on a node. Editor-side — no game needed.

    Args:
        action: "get_position", "look_at", or "focus_node".
        position: [x, y, z] for look_at — camera position.
        target: [x, y, z] for look_at — camera target.
        node: Node name for focus_node.
        detail: Output verbosity — "brief" (summary), "normal" (default), or "full" (everything).
    """
    try:
        return await _camera(action=action, position=position, target=target, node=node)
    except BridgeConnectionError as e:
        return {"error": str(e), "hint": "Enable the GodotIQ addon in Godot editor and ensure it is running."}
    except BridgeTimeoutError as e:
        return {"error": str(e), "hint": "The operation timed out."}
    except BridgeError as e:
        return {"error": f"[{e.code}] {e.error_message}"}
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


@mcp.tool(
    name="godotiq_ui_map",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": True,
    },
)
@guard_tool("godotiq_ui_map", configure_bridge=True)
async def godotiq_ui_map(
    root: str = "",
    include_invisible: bool = False,
    max_depth: int = 10,
    session_id: int | None = None,
    detail: str = "full",
    ctx: Context = None,
    *,
    max_output_nodes: int = 200,
    max_visited_nodes: int = 5000,
) -> dict:
    """Map all UI elements on screen: positions, text, interactivity, visibility. Call BEFORE godotiq_input to know what buttons/controls exist. Game must be running.

    Args:
        root: Root node name (e.g. "GameHUD"). Empty = entire UI tree.
        include_invisible: Include hidden elements (default false).
        max_depth: Tree traversal depth (default 10).
        max_output_nodes: Maximum UI records returned.
        max_visited_nodes: Maximum scene nodes inspected.
        detail: "brief" (interactive elements only + count), "normal" (default), "full" (+ modulate, mouse_filter, script).
    """
    try:
        return await _ui_map(
            root=root,
            include_invisible=include_invisible,
            max_depth=max_depth,
            max_output_nodes=max_output_nodes,
            max_visited_nodes=max_visited_nodes,
            session_id=session_id,
            detail=detail,
        )
    except BridgeConnectionError as e:
        return {"error": str(e), "hint": "Enable the GodotIQ addon in Godot editor and ensure it is running."}
    except BridgeTimeoutError as e:
        return {"error": str(e), "hint": "The game must be running. Start it with godotiq_run first."}
    except BridgeError as e:
        return {"error": f"[{e.code}] {e.error_message}"}
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


@mcp.tool(
    name="godotiq_build_scene",
    annotations={
        "readOnlyHint": False,
        "destructiveHint": True,
        "idempotentHint": False,
        "openWorldHint": True,
    },
)
@guard_tool("godotiq_build_scene", configure_bridge=True)
async def godotiq_build_scene(
    target_scene: str = "",
    parent: str = "",
    detail: str = "brief",
    grid: dict | None = None,
    line: dict | None = None,
    scatter: dict | None = None,
    nodes: list[dict] | None = None,
    offset: list[float] | None = None,
    ctx: Context = None,
) -> dict:
    """Create multiple nodes in a scene using high-level patterns. One call = many nodes with Ctrl+Z undo. Use INSTEAD of repeated node_ops add_child calls.

    Modes (exactly one required):
        grid: Place nodes in a rows x cols grid. Keys: rows (int), cols (int), spacing (float, auto-detected from GLB bounds if omitted), tile_size (float, optional explicit tile dimension), scene (res:// path), type (node type). Override keys use 'row,col' format (row=Z axis, col=X axis). Both 'row,col' and 'row_col' accepted. Spacing priority: explicit spacing > tile_size > GLB auto-detect > 1.0 default.
        line: Place nodes along a polyline path. Keys: points (list of [x,y,z]), spacing (float, default 1.0), scene, type.
        scatter: Place nodes at explicit positions. Keys: items (list of {scene, position, rotation, scale}).
        nodes: Explicit node list. Each dict: {type, name, position, rotation, scale, properties, scene}.

    Args:
        target_scene: .tscn path for context (auto-detects if empty).
        parent: Parent node path (e.g. "Level/Props"). Empty = scene root.
        detail: Output verbosity -- "brief" (default), "normal", "full".
        grid: Grid pattern config.
        line: Line pattern config.
        scatter: Scatter placement config.
        nodes: Explicit node definitions.
        offset: Shift entire pattern by [x, y, z] (default [0, 0, 0]). Applies to all modes.
    """
    # Auto-spacing resolution for grid mode (Section 8)
    auto_spacing_meta = None
    if grid is not None and "spacing" not in grid:
        auto_spacing_meta = _resolve_auto_spacing(grid, ctx)

    try:
        result = await _build_scene(
            grid=grid, line=line, scatter=scatter, nodes=nodes,
            parent=parent, target_scene=target_scene, offset=offset,
        )
        if "error" in result:
            return result
        if auto_spacing_meta is not None:
            result["auto_spacing"] = auto_spacing_meta
        return apply_output_limit(result, detail, list_keys=["errors"])
    except BridgeConnectionError as e:
        return {"error": str(e), "hint": "Enable the GodotIQ addon in Godot editor and ensure it is running."}
    except BridgeTimeoutError as e:
        return {"error": str(e), "hint": "Build may have timed out. Check editor for partial results."}
    except BridgeError as e:
        return {"error": f"[{e.code}] {e.error_message}"}
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


@mcp.tool(
    name="godotiq_check_errors",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": True,
    },
)
@guard_tool("godotiq_check_errors", configure_bridge=True)
async def godotiq_check_errors(scope: str = "scene", ctx: Context = None) -> dict:
    """Cheap text-only GDScript compilation/parse check. Use this before run/play and after script edits. For runtime/debugger errors from the Godot Debugger panel, use godotiq_read_debug_console instead of screenshots or asking the user to copy/paste.

    Args:
        scope: "scene" (current scene + autoloads), "project" (all .gd files),
               or "res://path/to/script.gd" (single file)
    """
    try:
        result = await _check_errors(scope=scope)
        return apply_output_limit(result, "full")
    except BridgeConnectionError as e:
        return {"error": str(e), "hint": "Enable the GodotIQ addon in Godot editor and ensure it is running."}
    except BridgeTimeoutError as e:
        return {"error": str(e), "hint": "The operation timed out. Try a smaller scope."}
    except BridgeError as e:
        return {"error": f"[{e.code}] {e.error_message}"}
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


@mcp.tool(
    name="godotiq_read_debug_console",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": True,
    },
)
@guard_tool("godotiq_read_debug_console", configure_bridge=True)
async def godotiq_read_debug_console(
    limit: int = 20,
    clear: bool = False,
    include_runtime: bool = True,
    include_script: bool = True,
    ctx: Context = None,
) -> dict:
    """Cheap text-only reader for Godot Debugger/console errors. Use this FIRST when the game errors, before screenshots, and do not ask the user to copy/paste the Debug window.

    Args:
        limit: Maximum entries to return (1-100). Defaults to 20.
        clear: Clear captured buffers after reading. Defaults to false.
        include_runtime: Include runtime errors captured from the running game.
        include_script: Include script parse/compile errors captured by the editor logger.
    """
    try:
        result = await _read_debug_console(
            limit=limit,
            clear=clear,
            include_runtime=include_runtime,
            include_script=include_script,
        )
        return apply_output_limit(result, "full")
    except BridgeConnectionError as e:
        return {"error": str(e), "hint": "Enable the GodotIQ addon in Godot editor and ensure it is running."}
    except BridgeTimeoutError as e:
        return {"error": str(e), "hint": "The operation timed out. Try a smaller limit."}
    except BridgeError as e:
        return {"error": f"[{e.code}] {e.error_message}"}
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


@mcp.tool(
    name="godotiq_verify_project_runs",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": True,
    },
)
@guard_tool("godotiq_verify_project_runs", configure_bridge=True)
async def godotiq_verify_project_runs(
    scene: str = "main",
    check_scope: str = "scene",
    startup_timeout: float = 0,
    settle_seconds: float = 1.0,
    error_limit: int = 20,
    stop_after: bool = True,
    fail_on_warnings: bool = False,
    ctx: Context = None,
) -> dict:
    """Conservative Play-mode verification. Use after code changes before claiming done. Returns PASS only if scripts compile, Play starts, and debug console has no failing errors.

    Args:
        scene: "main", "current", scene name, or "res://path.tscn".
        check_scope: "scene", "project", or a single "res://script.gd" preflight scope.
        startup_timeout: Seconds to wait for Play startup; 0 auto-detects project size.
        settle_seconds: Seconds to wait after Play starts before reading errors.
        error_limit: Maximum debug entries to return.
        stop_after: Stop the game after verification.
        fail_on_warnings: Treat warnings as FAIL instead of returning PASS with warnings.
    """
    try:
        session = get_session_from_ctx(ctx)
        project_root = session.root if session is not None else None
        result = await _verify_project_runs(
            scene=scene,
            check_scope=check_scope,
            startup_timeout=startup_timeout,
            settle_seconds=settle_seconds,
            error_limit=error_limit,
            stop_after=stop_after,
            fail_on_warnings=fail_on_warnings,
            project_root=project_root,
        )
        return apply_output_limit(result, "full")
    except Exception as e:
        return {"verdict": "INCONCLUSIVE", "phase": "tool_error", "error": f"Unexpected error: {e}"}


@mcp.tool(
    name="godotiq_verify_motion",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": True,
    },
)
@guard_tool("godotiq_verify_motion", configure_bridge=True)
async def godotiq_verify_motion(
    node: str,
    property_name: str = "position",
    duration: float = 2.0,
    session_id: int | None = None,
    detail: str = "full",
    ctx: Context = None,
) -> dict:
    """Verify a node property changes over time (proves movement/animation).

    Takes two state_inspect snapshots separated by a sleep and compares values.
    Use instead of screenshots to verify motion. Game must be running.

    Args:
        node: Node path or name to inspect.
        property_name: Property to monitor (default "position").
        duration: Seconds to wait between snapshots (default 2.0).
        detail: Output verbosity — "brief", "normal", or "full".
    """
    try:
        result = await _verify_motion(
            node=node, property_name=property_name, duration=duration, session_id=session_id,
        )
        return apply_output_limit(result, detail)
    except BridgeConnectionError as e:
        return {"error": str(e), "hint": "Enable the GodotIQ addon in Godot editor and ensure it is running."}
    except BridgeTimeoutError as e:
        return {"error": str(e), "hint": "The operation timed out. The game may have stopped."}
    except BridgeError as e:
        return {"error": f"[{e.code}] {e.error_message}"}
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


# ── Explore stub (testable async function) ──────────────────────────


async def _stub_explore(
    session: object | None,
    scene: str,
    mode: str,
    positions: list[dict] | None,
    max_areas: int,
    screenshots_per_area: int,
    scale: float,
    quality: float,
    fov: float,
    eye_height: float,
) -> dict:
    """Stub logic for godotiq_explore.

    Delegates to Pro bundle when available (with bridge error wrapping),
    or returns a community preview with teaser data when not.
    """
    if session is None:
        return {"error": "No Godot project loaded"}

    impl = get_pro_implementation("godotiq_explore")
    if impl is not None:
        try:
            return await impl(
                session, scene, mode, positions, max_areas,
                screenshots_per_area, scale, quality, fov, eye_height,
            )
        except BridgeConnectionError as e:
            return {"error": str(e), "hint": "Enable the GodotIQ addon in Godot editor and ensure it is running."}
        except BridgeTimeoutError as e:
            return {"error": str(e), "hint": "The operation timed out. The game may have stopped."}
        except BridgeError as e:
            return {"error": f"[{e.code}] {e.error_message}"}
        except Exception as e:
            return {"error": f"Unexpected error: {e}"}

    teaser = {
        "areas_inspected": 0,
        "total_screenshots": 0,
        "total_nodes": 0,
    }
    return pro_unavailable_response("godotiq_explore", teaser)


@mcp.tool(
    name="godotiq_explore",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": True,
    },
)
@guard_tool("godotiq_explore", configure_bridge=True)
async def godotiq_explore(
    scene: str = "",
    mode: str = "tour",
    positions: list[dict] | None = None,
    max_areas: int = 3,
    screenshots_per_area: int = 1,
    scale: float = 0.3,
    quality: float = 0.4,
    fov: float = 70.0,
    eye_height: float = 2.5,
    ctx: Context = None,
) -> dict:
    """Autonomous visual inspection of the running game via drone camera.

    Creates a temporary Camera3D in the game, flies it through calculated
    positions, captures screenshots, then restores the original camera.
    Has an 80K character budget — stops early and returns partial results if exceeded.

    Args:
        scene: res:// path to .tscn scene. Empty = use current editor scene.
        mode: "tour" (auto-cluster areas) or "inspect" (explicit positions).
        positions: For inspect mode: list of dicts with position/look_at/direction.
        max_areas: Max spatial clusters to visit in tour mode (default 3).
        screenshots_per_area: Positions per cluster (1=overview, 5=all cardinals).
        scale: Screenshot scale factor (0.0-1.0, default 0.3 for token efficiency).
        quality: Screenshot encoding quality (0.0-1.0, default 0.4 for token efficiency).
        fov: Drone camera field of view in degrees.
        eye_height: Height offset for cardinal camera positions.
    """
    session = ctx.request_context.lifespan_context.get("session") if ctx else None
    return await _stub_explore(
        session, scene, mode, positions, max_areas,
        screenshots_per_area, scale, quality, fov, eye_height,
    )


@mcp.tool(
    name="godotiq_game_scene_tree",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": True,
    },
)
@guard_tool("godotiq_game_scene_tree", configure_bridge=True)
async def godotiq_game_scene_tree(
    root: str = "",
    depth: int = 3,
    filter_type: str = "",
    session_id: int | None = None,
    detail: str = "full",
    ctx: Context = None,
    *,
    max_output_nodes: int = 200,
    max_visited_nodes: int = 5000,
) -> dict:
    """Query the running game's actual scene tree. Unlike godotiq_scene_tree (editor-side, stale after scene transitions), this returns live runtime data. Game must be running.

    Args:
        root: Node path to start from (e.g. "/root/Main"). Empty = /root.
        depth: Max tree depth (1-10, default 3).
        filter_type: Only include nodes of this type (e.g. "Button").
        max_output_nodes: Maximum node records returned.
        max_visited_nodes: Maximum scene nodes inspected.
        detail: Output verbosity — "brief" (summary), "normal" (default), or "full" (everything).
    """
    try:
        result = await _game_scene_tree(
            root=root,
            depth=depth,
            filter_type=filter_type,
            max_output_nodes=max_output_nodes,
            max_visited_nodes=max_visited_nodes,
            session_id=session_id,
        )
        return apply_output_limit(result, detail)
    except BridgeConnectionError as e:
        return {"error": str(e), "hint": "Enable the GodotIQ addon in Godot editor and ensure it is running."}
    except BridgeTimeoutError as e:
        return {"error": str(e), "hint": "Game may not be running or the operation timed out."}
    except BridgeError as e:
        return {"error": f"[{e.code}] {e.error_message}"}
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


@mcp.tool(
    name="godotiq_press_button",
    annotations={
        "readOnlyHint": False,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": True,
    },
)
@guard_tool("godotiq_press_button", configure_bridge=True)
async def godotiq_press_button(
    name: str = "",
    root: str = "",
    session_id: int | None = None,
    detail: str = "full",
    ctx: Context = None,
    *,
    max_visited_nodes: int = 5000,
) -> dict:
    """Trigger a button's pressed signal in the running game by name. Unlike godotiq_input tap (mouse simulation), this directly emits the pressed signal. Works for buttons inside ScrollContainer. Game must be running.

    Args:
        name: Button node name to find and press (e.g. "@Button@44").
        root: Optional root node path to search from (e.g. "/root/Main/MapScreen").
        max_visited_nodes: Maximum scene nodes inspected.
        detail: Output verbosity — "brief" (summary), "normal" (default), or "full" (everything).
    """
    try:
        result = await _press_button(
            name=name,
            root=root,
            max_visited_nodes=max_visited_nodes,
            session_id=session_id,
        )
        return apply_output_limit(result, detail)
    except BridgeConnectionError as e:
        return {"error": str(e), "hint": "Enable the GodotIQ addon in Godot editor and ensure it is running."}
    except BridgeTimeoutError as e:
        return {"error": str(e), "hint": "Game may not be running or the operation timed out."}
    except BridgeError as e:
        return {"error": f"[{e.code}] {e.error_message}"}
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


@mcp.tool(
    name="godotiq_find_node",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": True,
    },
)
@guard_tool("godotiq_find_node", configure_bridge=True)
async def godotiq_find_node(
    name: str = "",
    root: str = "",
    session_id: int | None = None,
    detail: str = "full",
    ctx: Context = None,
    *,
    max_visited_nodes: int = 5000,
) -> dict:
    """Find a single node by name in the running game's scene tree. Returns the node's info (type, path, position, etc.) or found=false. Much faster than godotiq_game_scene_tree for checking if a specific node exists. Game must be running.

    Args:
        name: Node name to search for (e.g. "BattleHudLayer").
        root: Optional root node path to search from.
        max_visited_nodes: Maximum scene nodes inspected.
        detail: Output verbosity — "brief" (summary), "normal" (default), or "full" (everything).
    """
    try:
        result = await _find_node(
            name=name,
            root=root,
            max_visited_nodes=max_visited_nodes,
            session_id=session_id,
        )
        return apply_output_limit(result, detail)
    except BridgeConnectionError as e:
        return {"error": str(e), "hint": "Enable the GodotIQ addon in Godot editor and ensure it is running."}
    except BridgeTimeoutError as e:
        return {"error": str(e), "hint": "Game may not be running or the operation timed out."}
    except BridgeError as e:
        return {"error": f"[{e.code}] {e.error_message}"}
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}


@mcp.tool(
    name="godotiq_reload_addon",
    annotations={
        "readOnlyHint": False,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    },
)
@guard_tool("godotiq_reload_addon", configure_bridge=True)
async def godotiq_reload_addon(
    detail: str = "full",
    ctx: Context = None,
) -> dict:
    """Hot-reload all GodotIQ addon scripts to pick up new tools/capabilities. Use after modifying addon GDScript files. No plugin disable/enable needed.

    Args:
        detail: Output verbosity — "brief" (summary), "normal" (default), or "full" (everything).
    """
    try:
        result = await _reload_addon()
        return apply_output_limit(result, detail)
    except BridgeConnectionError as e:
        return {"error": str(e), "hint": "Enable the GodotIQ addon in Godot editor and ensure it is running."}
    except BridgeTimeoutError as e:
        return {"error": str(e), "hint": "The operation timed out."}
    except BridgeError as e:
        return {"error": f"[{e.code}] {e.error_message}"}
    except Exception as e:
        return {"error": f"Unexpected error: {e}"}
