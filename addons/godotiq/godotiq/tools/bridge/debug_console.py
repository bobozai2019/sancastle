"""Read Godot debug/error buffers through the editor bridge."""

from __future__ import annotations

from godotiq.bridge.session import get_bridge


async def read_debug_console(
    limit: int = 20,
    clear: bool = False,
    include_runtime: bool = True,
    include_script: bool = True,
) -> dict:
    """Return recent runtime and script errors captured by the Godot addon.

    Args:
        limit: Maximum number of entries to return.
        clear: Whether to clear buffers after reading them.
        include_runtime: Include recent runtime errors reported by the debugger bridge.
        include_script: Include script parse/compile errors captured by the editor logger.

    Returns:
        Dict with entries, counts, capture capabilities, and truncation metadata.
    """
    bridge = await get_bridge()
    params = {
        "limit": max(1, min(int(limit), 100)),
        "clear": bool(clear),
        "include_runtime": bool(include_runtime),
        "include_script": bool(include_script),
    }
    return await bridge.request("read_debug_console", params=params)
