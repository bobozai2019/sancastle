"""A08 — godotiq_exec: Execute arbitrary GDScript.

Supports two contexts:
- "game" (default): Runs in game process via EngineDebugger. RefCounted sandbox,
  no get_node/get_tree. Only Engine.* and static APIs. Game must be running.
- "editor": Runs in editor process. Full access to EditorInterface,
  get_tree(), edited scene root, all editor nodes. Like GDAI's execute_editor_script.
"""

from __future__ import annotations

import re

from godotiq.bridge.session import get_bridge

# Defense-in-depth: blocked patterns matching the GDScript side.
# Keep in sync with godotiq_server.gd and godotiq_runtime.gd blocked_patterns arrays.
_BLOCKED_PATTERNS: tuple[str, ...] = (
    "DirAccess.remove",
    "DirAccess.open",
    "FileAccess.open",
    "FileAccess.get_file_as_string",
    "FileAccess.get_file_as_bytes",
    "OS.execute",
    "OS.kill",
    "OS.shell_open",
)

# Catches: var FA = FileAccess, var DA : Variant = DirAccess, etc.
_ALIAS_RE = re.compile(r"var\s+\w+[^=]*=\s*(FileAccess|DirAccess)\b")

TOOL_NAME = "godotiq_exec"
TOOL_DESCRIPTION = (
    "Execute arbitrary GDScript code. "
    "context='game' (default): runs in game sandbox with limited access. Game must be running. "
    "context='editor': runs in editor with full access to EditorInterface, "
    "get_tree(), scene nodes. Use for editor queries and modifications. "
    "Code MUST contain 'func run():'. Return value is stringified. "
    "WARNING: execution is synchronous. timeout_ms limits how long the bridge "
    "waits for a response; it cannot cancel code already running in Godot. "
    "Do not use exec for large saves, scene baking, or long await chains."
)


def _bridge_timeout_seconds(timeout_ms: int) -> float:
    """Give the addon enough time to return a structured timeout/error response."""
    requested_seconds = max(timeout_ms, 0) / 1000.0
    return max(requested_seconds + 2.0, 5.0)


async def exec_code(
    code: str = "",
    context: str = "game",
    timeout_ms: int = 15000,
    session_id: int | None = None,
) -> dict:
    """Execute GDScript code.

    Args:
        code: GDScript code containing 'func run():'. The return value of run()
            will be stringified and returned.
        context: "game" (default) — sandbox, or "editor" — full editor access.
        timeout_ms: Bridge response timeout in milliseconds (default 15000,
            min 1000, max 30000). It does not terminate GDScript already running.

    Game context examples:
        code="func run():\\n\\treturn Engine.get_version_info()"
        code="func run():\\n\\treturn Engine.get_frames_per_second()"

    Editor context examples:
        code="func run():\\n\\tvar root = get_tree().edited_scene_root\\n\\treturn root.name"
        code="func run():\\n\\treturn get_tree().edited_scene_root.get_child_count()"
        code="func run():\\n\\treturn str(EditorInterface.get_edited_scene_root().scene_file_path)"

    Returns:
        Dict with status (OK/BLOCKED/COMPILE_ERROR/ERROR), result (string), error.

    Warning:
        func run() must return quickly and synchronously. A timeout only stops
        waiting for the response; the operation may still be running in Godot.
    """
    if not code:
        return {"status": "ERROR", "result": "", "error": "No code provided"}

    if context not in ("editor", "game"):
        return {
            "status": "ERROR",
            "result": "",
            "error": f"Invalid context: {context}. Use 'editor' or 'game'.",
        }

    timeout_ms = min(max(timeout_ms, 1000), 30000)

    # Defense-in-depth: check for blocked patterns before sending to bridge.
    # This is best-effort — GDScript lacks eval(), so string-based construction
    # can build strings but cannot execute them as code. The real sandbox in game
    # context is the RefCounted base class (no scene tree access). Editor context
    # is inherently trusted (full editor access by design) but we block obvious
    # data corruption patterns. Pattern matching is NOT a security boundary.
    for pattern in _BLOCKED_PATTERNS:
        if pattern in code:
            return {"status": "BLOCKED", "result": "", "error": f"Blocked pattern: {pattern}"}

    alias_match = _ALIAS_RE.search(code)
    if alias_match:
        return {
            "status": "BLOCKED",
            "result": "",
            "error": f"Indirect reference to blocked class: {alias_match.group(1)}",
        }

    bridge = await get_bridge()
    request_timeout = _bridge_timeout_seconds(timeout_ms)

    if context == "editor":
        result = await bridge.request("exec_editor", params={
            "code": code,
            "timeout_ms": timeout_ms,
        }, timeout=request_timeout)
    else:
        params = {
            "code": code,
            "timeout_ms": timeout_ms,
        }
        if session_id is not None:
            params["session_id"] = session_id
        result = await bridge.request("exec", params=params, timeout=request_timeout)

    return _format_error_detail(result)


def _format_error_detail(result: dict) -> dict:
    """Format structured error_detail from bridge COMPILE_ERROR responses.

    If the bridge returns an ``error_detail`` list of
    ``{"line": int, "message": str}`` entries, join them into a
    human-readable string.  Empty or missing lists are removed so
    callers only see the key when there is real data.
    """
    raw = result.get("error_detail")
    if not isinstance(raw, list) or not raw:
        result.pop("error_detail", None)
        return result

    parts = [
        f"line {e['line']}: {e['message']}"
        for e in raw
        if isinstance(e, dict) and "line" in e and "message" in e
    ]
    if parts:
        result["error_detail"] = "; ".join(parts)
    else:
        result.pop("error_detail", None)
    return result
