"""Node operations tool -- batch node editing with undo/redo support."""

from __future__ import annotations

from godotiq.bridge.session import get_bridge
from godotiq.tools.bridge.spatial_validator import validate_move, validate_scale

MAX_OPERATIONS = 50


async def node_ops(operations: list[dict], scene_data: dict | None = None) -> dict:
    """Execute batch node operations with optional spatial validation.

    When scene_data is provided and an operation has validate:true,
    the operation is checked against scene spatial context before execution.

    Each operation is a dict with an 'op' key and operation-specific params.
    All operations are grouped as a single undo action in the editor.

    Supported operations:
        move, rotate, scale, set_property, add_child, delete, duplicate, reparent, rename, get_property

    Parameter aliasing:
        For move, rotate, and scale operations, the data key can be either the
        specific name or the generic "value" alias:
        - move: "position" (preferred) or "value"
        - rotate: "rotation" (preferred) or "value"
        - scale: "scale" (preferred) or "value"
        When both the specific key and "value" are present, the specific key
        takes priority.

    Args:
        operations: List of operation dicts. Must be non-empty and at most 50 items.
        scene_data: Optional scene spatial data for validation. When None, validation
            is skipped even if operations have validate:true.

    Returns:
        Dict with 'results' list containing per-operation status dicts.
        If validation blocks, returns dict with 'status': 'BLOCKED' instead.

    Raises:
        ValueError: If operations list is empty or exceeds the 50-operation limit.
    """
    if not operations:
        raise ValueError("No operations provided; at least one operation is required.")
    if len(operations) > MAX_OPERATIONS:
        raise ValueError(
            f"Too many operations ({len(operations)}); limit is {MAX_OPERATIONS} per call."
        )

    # Pre-flight validation for rename and get_property
    for op in operations:
        op_type = op.get("op", "")
        if op_type == "rename":
            if not op.get("node"):
                raise ValueError("rename operation requires a non-empty 'node' field.")
            if not op.get("new_name"):
                raise ValueError("rename operation requires a non-empty 'new_name' field.")
        elif op_type == "get_property":
            if not op.get("node"):
                raise ValueError("get_property operation requires a non-empty 'node' field.")
            if not op.get("property"):
                raise ValueError("get_property operation requires a non-empty 'property' field.")

    requested_validation = any(op.get("validate") for op in operations)
    if requested_validation and scene_data is None:
        return {
            "status": "BLOCKED",
            "error": "validation_unavailable",
            "code": "VALIDATION_UNAVAILABLE",
            "message": "Spatial validation requested but no scene data was available. No changes made.",
            "operations_blocked": sum(1 for op in operations if op.get("validate")),
        }

    # Validation
    validations: list[dict] = []
    has_validate = scene_data is not None and requested_validation

    if has_validate:
        for op in operations:
            if not op.get("validate"):
                continue
            result = None
            op_type = op.get("op")
            if op_type == "move":
                pos_key = "position" if "position" in op else ("value" if "value" in op else None)
                if pos_key:
                    result = validate_move(op[pos_key], op.get("node", ""), scene_data)
            elif op_type == "scale":
                sc_key = "scale" if "scale" in op else ("value" if "value" in op else None)
                if sc_key:
                    result = validate_scale(op[sc_key], op.get("node", ""), scene_data)
            elif op_type == "add_child":
                pos_key = "position" if "position" in op else ("value" if "value" in op else None)
                if pos_key:
                    result = validate_move(op[pos_key], op.get("node", op.get("name", "")), scene_data)
            if result is not None:
                validations.append(result)

        blocked_count = sum(1 for v in validations if v.get("severity") == "BLOCKED")
        if blocked_count > 0:
            return {
                "status": "BLOCKED",
                "validation": validations,
                "message": "One or more operations blocked by spatial validation. No changes made.",
                "operations_blocked": blocked_count,
            }

    bridge = await get_bridge()
    result = await bridge.request("node_ops", params={"operations": operations})

    if validations:
        result["validation"] = validations

    return result
