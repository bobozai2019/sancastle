"""Output size limiting for MCP tool responses.

Enforces character limits on tool output to prevent context window overflow.
All tools returning variable-size data should call apply_output_limit() before
returning their result dict.
"""

from __future__ import annotations

import json
import logging

logger = logging.getLogger(__name__)

# Character limits per detail level
_CHAR_LIMITS: dict[str, int | None] = {
    "brief": 2000,
    "normal": 8000,
    "full": None,  # No limit
}

_VALID_DETAIL_VALUES = {"brief", "normal", "full"}

_TRUNCATION_MSG = "Output truncated. Use detail='full' to see everything."


def _normalize_detail(detail: str) -> str:
    """Normalize detail value, defaulting unknown values to 'normal'."""
    if detail not in _VALID_DETAIL_VALUES:
        logger.warning("Unknown detail value %r, normalizing to 'normal'", detail)
        return "normal"
    return detail


def _estimate_size(result: dict) -> int:
    """Estimate JSON-serialized character count."""
    return len(json.dumps(result, default=str, ensure_ascii=False))


def apply_output_limit(
    result: dict,
    detail: str,
    list_keys: list[str] | None = None,
) -> dict:
    """Enforce character limits on tool output.

    Progressively truncates lists in the result dict until output
    fits within the character limit for the given detail level.

    Args:
        result: The tool result dict.
        detail: "brief", "normal", or "full".
        list_keys: Keys in result that contain truncatable lists.
            If None, auto-detects all list-valued keys.

    Returns:
        The (possibly truncated) result dict.
    """
    detail = _normalize_detail(detail)
    limit = _CHAR_LIMITS.get(detail)
    if limit is None:
        return result

    # Preserve _editor_state — extract before truncation, re-inject after
    editor_state = result.pop("_editor_state", None)

    size = _estimate_size(result)
    if size <= limit:
        if editor_state is not None:
            result["_editor_state"] = editor_state
        return result

    # Auto-detect list keys if not provided
    if list_keys is None:
        list_keys = [k for k, v in result.items() if isinstance(v, list) and len(v) > 1]

    # Sort by list length descending — truncate largest lists first
    list_keys = sorted(list_keys, key=lambda k: len(result.get(k, [])), reverse=True)

    # Reserve space for truncation metadata (~200 chars)
    _METADATA_OVERHEAD = 200
    effective_limit = limit - _METADATA_OVERHEAD

    for key in list_keys:
        if key not in result or not isinstance(result[key], list):
            continue

        original_len = len(result[key])
        if original_len <= 1:
            continue

        # Binary search for the right truncation point
        lo, hi = 0, original_len
        original_list = result[key]

        while lo < hi:
            mid = (lo + hi + 1) // 2
            result[key] = original_list[:mid]
            if _estimate_size(result) <= effective_limit:
                lo = mid
            else:
                hi = mid - 1

        result[key] = original_list[:lo] if lo > 0 else original_list[:1]
        kept = len(result[key])

        if kept < original_len:
            omitted = original_len - kept
            result[f"{key}_total"] = original_len
            result["output_truncated"] = True
            result["truncation_notice"] = (
                f"{_TRUNCATION_MSG} {omitted} item(s) omitted from '{key}'."
            )

        size = _estimate_size(result)
        if size <= limit:
            break

    # Re-inject preserved _editor_state
    if editor_state is not None:
        result["_editor_state"] = editor_state

    return result


def truncate_output(text: str, detail: str, tool_name: str = "") -> str:
    """Truncate raw text output to fit detail-level character limits.

    Safety net for string-based output. Uses the same character limits as
    apply_output_limit() (brief=2000, normal=8000, full=unlimited).

    Args:
        text: The raw text to potentially truncate.
        detail: "brief", "normal", or "full".
        tool_name: Optional tool name for the truncation notice.

    Returns:
        The (possibly truncated) text with a notice appended if truncated.
    """
    if not text:
        return text

    detail = _normalize_detail(detail)
    limit = _CHAR_LIMITS.get(detail)
    if limit is None:
        return text

    if len(text) <= limit:
        return text

    # Reserve 200 chars for the truncation notice
    cut_point = limit - 200
    truncated = text[:cut_point]
    remaining = text[cut_point:]
    remaining_lines = remaining.count("\n") + 1

    tool_label = f" [{tool_name}]" if tool_name else ""
    notice = f"\n\n...{tool_label} truncated ({remaining_lines} more lines). Use detail='full' for complete output."
    return truncated + notice
