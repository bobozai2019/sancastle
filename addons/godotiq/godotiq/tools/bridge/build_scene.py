"""Build scene tool -- batch node creation with high-level patterns."""

from __future__ import annotations

import math

from godotiq.bridge.session import get_bridge

MAX_NODES = 256


def validate_build_params(
    grid: dict | None,
    line: dict | None,
    scatter: dict | None,
    nodes: list[dict] | None,
    offset: list[float] | None = None,
) -> tuple[dict | None, dict | None]:
    """Validate build_scene parameters.

    Returns (params_dict, None) on success, or (None, error_dict) on failure.
    """
    # Validate offset first
    if offset is not None:
        if not isinstance(offset, (list, tuple)) or len(offset) != 3:
            return None, {"error": "offset must be a list of exactly 3 numbers [x, y, z]"}
        if not all(isinstance(el, (int, float)) for el in offset):
            return None, {"error": "offset must be a list of exactly 3 numbers [x, y, z]"}

    resolved_offset = list(offset) if offset is not None else [0, 0, 0]

    modes = [(k, v) for k, v in [("grid", grid), ("line", line), ("scatter", scatter), ("nodes", nodes)] if v is not None]

    if len(modes) == 0:
        return None, {"error": "Exactly one mode required: grid, line, scatter, or nodes. None provided."}
    if len(modes) > 1:
        names = ", ".join(k for k, _ in modes)
        return None, {"error": f"Exactly one mode required, but got multiple: {names}."}

    mode_name, mode_value = modes[0]

    if mode_name == "grid":
        params, error = _validate_grid(mode_value)
    elif mode_name == "line":
        params, error = _validate_line(mode_value)
    elif mode_name == "scatter":
        params, error = _validate_scatter(mode_value)
    else:
        params, error = _validate_nodes(mode_value)

    if error is not None:
        return None, error

    params["offset"] = resolved_offset
    return params, None


def _validate_grid(grid: dict) -> tuple[dict | None, dict | None]:
    """Validate grid mode parameters.

    Accepted keys: rows, cols, spacing, scene, type, overrides, tile_size.
    tile_size is consumed by auto-spacing logic and stripped before bridge call.
    """
    if "rows" not in grid:
        return None, {"error": "Grid mode requires 'rows' key."}
    if "cols" not in grid:
        return None, {"error": "Grid mode requires 'cols' key."}
    rows = grid["rows"]
    cols = grid["cols"]
    if not isinstance(rows, int) or rows <= 0:
        return None, {"error": f"Grid 'rows' must be a positive integer, got {rows}."}
    if not isinstance(cols, int) or cols <= 0:
        return None, {"error": f"Grid 'cols' must be a positive integer, got {cols}."}
    count = rows * cols
    if count > MAX_NODES:
        return None, {"error": f"Grid would create {count} nodes, exceeding the {MAX_NODES} limit."}
    # Strip tile_size before forwarding (consumed by auto-spacing at wrapper level)
    clean_grid = {k: v for k, v in grid.items() if k != "tile_size"}
    return {"grid": clean_grid}, None


def _validate_line(line: dict) -> tuple[dict | None, dict | None]:
    """Validate line mode parameters."""
    points = line.get("points")
    if not points or not isinstance(points, list):
        return None, {"error": "Line mode requires 'points' array with at least 2 points."}
    if len(points) < 2:
        return None, {"error": "Line mode requires at least 2 points."}
    # Estimate node count from total distance / spacing
    spacing = line.get("spacing", 1.0)
    if spacing <= 0:
        return None, {"error": "Line 'spacing' must be positive."}
    # Validate point structure and compute total distance
    total_dist = 0.0
    for i, pt in enumerate(points):
        if not isinstance(pt, (list, tuple)) or len(pt) < 2:
            return None, {"error": f"Line point[{i}] must be a list of at least 2 numbers."}
    for i in range(len(points) - 1):
        a, b = points[i], points[i + 1]
        dx = b[0] - a[0]
        dy = b[1] - a[1]
        dz = (b[2] - a[2]) if len(a) > 2 and len(b) > 2 else 0
        total_dist += math.sqrt(dx * dx + dy * dy + dz * dz)
    estimated_count = int(total_dist / spacing) + 1
    if estimated_count > MAX_NODES:
        return None, {"error": f"Line would create ~{estimated_count} nodes, exceeding the {MAX_NODES} limit."}
    return {"line": line}, None


def _validate_scatter(scatter: dict) -> tuple[dict | None, dict | None]:
    """Validate scatter mode parameters."""
    items = scatter.get("items")
    if items is None:
        return None, {"error": "Scatter mode requires 'items' key."}
    if not isinstance(items, list) or len(items) == 0:
        return None, {"error": "Scatter 'items' must be a non-empty list."}
    if len(items) > MAX_NODES:
        return None, {"error": f"Scatter has {len(items)} items, exceeding the {MAX_NODES} limit."}
    return {"scatter": scatter}, None


def _validate_nodes(nodes: list[dict]) -> tuple[dict | None, dict | None]:
    """Validate nodes mode parameters."""
    if not nodes:
        return None, {"error": "Nodes list must be non-empty."}
    if len(nodes) > MAX_NODES:
        return None, {"error": f"Nodes list has {len(nodes)} items, exceeding the {MAX_NODES} limit."}
    return {"nodes": nodes}, None


def normalize_override_keys(overrides: dict) -> tuple[dict, list[str]]:
    """Normalize override keys: accept both 'row,col' and 'row_col' formats.

    Converts underscore-separated keys to comma-separated format for
    compatibility with the GDScript-side lookup which uses "%d,%d" % [row, col].

    Returns (normalized_dict, warnings) where warnings lists any key collisions.
    """
    normalized: dict = {}
    warnings: list[str] = []
    for key, value in overrides.items():
        norm_key = key.replace("_", ",", 1) if "_" in key and "," not in key else key
        if norm_key in normalized:
            warnings.append(
                f"Override key collision: '{key}' normalizes to '{norm_key}' "
                f"which already exists. Keeping the first value."
            )
            continue
        normalized[norm_key] = value
    return normalized, warnings


def check_override_bounds(overrides: dict, rows: int, cols: int) -> list[str]:
    """Check override keys against grid dimensions, warn on out-of-bounds.

    For each key, parses row,col and checks:
    - If row >= rows or col >= cols, emits a warning.
    - If swapping row/col would make both in-bounds, adds a transposition hint
      suggesting the correct format.

    Args:
        overrides: Dict with normalized 'row,col' string keys.
        rows: Number of grid rows.
        cols: Number of grid columns.

    Returns:
        List of warning strings (empty if all keys are in-bounds).
    """
    warnings: list[str] = []
    for key in overrides:
        parts = key.split(",")
        if len(parts) != 2:
            continue
        try:
            r, c = int(parts[0].strip()), int(parts[1].strip())
        except ValueError:
            continue
        if r < 0 or c < 0 or r >= rows or c >= cols:
            msg = f"Override key '{key}' is out of bounds for {rows}x{cols} grid."
            if r >= 0 and c >= 0 and c < rows and r < cols:
                msg += f" Did you mean '{c},{r}'? Keys use row,col format (row=Z, col=X)."
            warnings.append(msg)
    return warnings


def validate_grid_connectivity(overrides: dict, spacing: float) -> list[str]:
    """Validate that override tiles form a connected path with no isolated tiles.

    Uses 4-connectivity (up/down/left/right). Overrides with a custom 'position'
    key are excluded from validation since their world-space location doesn't
    match the grid layout.

    Override keys use 'row,col' format where row maps to the Z axis and col
    maps to the X axis.

    Args:
        overrides: Dict mapping "row,col" strings to override data dicts.
        spacing: Grid cell spacing (currently unused but passed for future use).

    Returns:
        List of warning strings for isolated tiles, or empty list if all valid.
    """
    if len(overrides) < 2:
        return []

    # Parse keys and filter out custom-position overrides
    coords: set[tuple[int, int]] = set()
    for key, value in overrides.items():
        if isinstance(value, dict) and "position" in value:
            continue
        parts = key.split(",")
        if len(parts) != 2:
            continue
        try:
            row, col = int(parts[0].strip()), int(parts[1].strip())
        except ValueError:
            continue
        coords.add((row, col))

    if len(coords) < 2:
        return []

    # Check 4-connectivity for each tile
    warnings: list[str] = []
    for row, col in sorted(coords):
        neighbors = [
            (row - 1, col),
            (row + 1, col),
            (row, col - 1),
            (row, col + 1),
        ]
        if not any(n in coords for n in neighbors):
            warnings.append(
                f"Isolated tile at ({row}, {col}) has no adjacent override neighbors"
            )

    return warnings


async def build_scene(
    grid: dict | None = None,
    line: dict | None = None,
    scatter: dict | None = None,
    nodes: list[dict] | None = None,
    parent: str = "",
    target_scene: str = "",
    offset: list[float] | None = None,
) -> dict:
    """Send a build_scene request to the Godot addon.

    Validates parameters first, then forwards to the bridge.

    Args:
        grid: Grid pattern config (rows, cols, spacing, scene).
              Override keys use 'row,col' format where row maps to the Z axis
              (0 = north/top) and col maps to the X axis (0 = west/left).
              Row comes first (matrix notation [row][col], not (x, y) order).
              Example: "2,5" = grid row 2, column 5, world pos ~(5*spacing, 0, 2*spacing).
              Both 'row,col' and 'row_col' key formats are accepted.
        line: Line pattern config (points, spacing, scene).
        scatter: Scatter config (items list with scene + position).
        nodes: Explicit node list (type, name, position, etc.).
        parent: Parent node path in the scene.
        target_scene: Target .tscn path for context.
        offset: Shift entire pattern by [x, y, z] (default [0, 0, 0]).

    Returns:
        Bridge response dict, or error dict if validation fails.
    """
    # Normalize override keys before validation and bridge call
    norm_warnings: list[str] = []
    if grid is not None and isinstance(grid.get("overrides"), dict):
        normalized, norm_warnings = normalize_override_keys(grid["overrides"])
        grid = {**grid, "overrides": normalized}

    params, error = validate_build_params(grid, line, scatter, nodes, offset=offset)
    if error is not None:
        return error

    bridge = await get_bridge()
    result = await bridge.request(
        "build_scene",
        params={**params, "parent": parent, "target_scene": target_scene},
    )

    # Validate grid connectivity and bounds after successful build
    if grid is not None and isinstance(grid.get("overrides"), dict):
        all_warnings: list[str] = list(norm_warnings)
        all_warnings.extend(validate_grid_connectivity(
            grid["overrides"],
            float(grid.get("spacing", 1.0)),
        ))
        all_warnings.extend(check_override_bounds(
            grid["overrides"],
            grid["rows"],
            grid["cols"],
        ))
        result["warnings"] = all_warnings

    return result
