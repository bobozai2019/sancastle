"""Parser for Godot TSCN property values.

Handles all value types found on the right-hand side of property assignments
in .tscn files: scalars, vectors, colors, transforms, references, arrays,
dictionaries, and packed arrays.
"""

from __future__ import annotations

import math
import re
import logging

logger = logging.getLogger(__name__)

# Pre-compiled regex patterns
_EXT_RESOURCE_RE = re.compile(r'^ExtResource\("([^"]+)"\)$')
_SUB_RESOURCE_RE = re.compile(r'^SubResource\("([^"]+)"\)$')
_NODE_PATH_RE = re.compile(r'^NodePath\("([^"]*)"\)$')
_STRING_NAME_RE = re.compile(r'^StringName\(&"([^"]*)"\)$')

# Type prefix → (expected_component_count, parse_as_int)
_FLOAT_TUPLE_TYPES: dict[str, int] = {
    "Vector2": 2,
    "Vector3": 3,
    "Vector4": 4,
    "Color": 4,
    "Rect2": 4,
    "Rect2i": 4,
    "AABB": 6,
    "Quaternion": 4,
    "Plane": 4,
    "Basis": 9,
    "Transform2D": 6,
    "Projection": 16,
}

_INT_TUPLE_TYPES: dict[str, int] = {
    "Vector2i": 2,
    "Vector3i": 3,
    "Vector4i": 4,
}

_PACKED_PREFIXES = (
    "PackedByteArray",
    "PackedInt32Array",
    "PackedInt64Array",
    "PackedFloat32Array",
    "PackedFloat64Array",
    "PackedStringArray",
    "PackedVector2Array",
    "PackedVector3Array",
    "PackedColorArray",
    "PackedVector4Array",
)

# Epsilon for floating-point noise cleanup
_NOISE_EPSILON = 1e-7
# Epsilon for gimbal lock detection (matches Godot PR #102144)
_GIMBAL_EPSILON = 0.00000025
# Epsilon for near-zero angle cleanup
_ANGLE_EPSILON = 1e-10


def parse_value(raw: str) -> object:
    """Parse a TSCN value string into a Python object.

    Args:
        raw: The raw string from the right-hand side of a property assignment.

    Returns:
        Parsed Python object (bool, int, float, str, tuple, list, dict, or raw string).
    """
    s = raw.strip()

    if not s:
        return ""

    # 1. Packed arrays — return raw string (performance: avoid regex on megabyte lines)
    if s.startswith("Packed"):
        for prefix in _PACKED_PREFIXES:
            if s.startswith(prefix):
                return s
        # Unknown Packed type, still return raw
        return s

    # 2. Known type prefixes
    # Reference types
    m = _EXT_RESOURCE_RE.match(s)
    if m:
        return {"type": "ext_resource", "id": m.group(1)}

    m = _SUB_RESOURCE_RE.match(s)
    if m:
        return {"type": "sub_resource", "id": m.group(1)}

    m = _NODE_PATH_RE.match(s)
    if m:
        return m.group(1)

    m = _STRING_NAME_RE.match(s)
    if m:
        return m.group(1)

    # Transform3D — special decomposition
    if s.startswith("Transform3D(") and s.endswith(")"):
        inner = s[len("Transform3D("):-1]
        try:
            values = tuple(float(x.strip()) for x in inner.split(","))
            if len(values) == 12:
                return decompose_transform3d(values)
        except (ValueError, IndexError):
            logger.warning("Malformed Transform3D: %s", s[:80])
        return s

    # Float tuple types (Vector3, Color, etc.)
    for prefix, count in _FLOAT_TUPLE_TYPES.items():
        if s.startswith(prefix + "(") and s.endswith(")"):
            inner = s[len(prefix) + 1:-1]
            try:
                parts = [float(x.strip()) for x in inner.split(",")]
                if len(parts) == count:
                    return tuple(parts)
            except ValueError:
                logger.warning("Malformed %s: %s", prefix, s[:80])
            return s

    # Int tuple types (Vector3i, etc.)
    for prefix, count in _INT_TUPLE_TYPES.items():
        if s.startswith(prefix + "(") and s.endswith(")"):
            inner = s[len(prefix) + 1:-1]
            try:
                parts = [int(x.strip()) for x in inner.split(",")]
                if len(parts) == count:
                    return tuple(parts)
            except ValueError:
                logger.warning("Malformed %s: %s", prefix, s[:80])
            return s

    # 3. Dictionary
    if s.startswith("{"):
        return _parse_dict(s)

    # 4. Array
    if s.startswith("["):
        return _parse_array(s)

    # 5. Quoted string
    if s.startswith('"') and s.endswith('"') and len(s) >= 2:
        return _unescape_string(s[1:-1])

    # 6. Scalar keywords (exact match only)
    if s == "true":
        return True
    if s == "false":
        return False
    if s == "null":
        return None

    # 7. Numeric
    try:
        if "." in s or "e" in s or "E" in s:
            return float(s)
        return int(s)
    except ValueError:
        pass

    # 8. Fallback — return raw string
    return s


def decompose_transform3d(
    values: tuple[float, ...],
) -> dict[str, tuple[float, float, float]]:
    """Decompose 12 Transform3D floats into position, rotation, scale.

    Args:
        values: 12 floats in Godot's column-major order:
            (b00, b10, b20, b01, b11, b21, b02, b12, b22, ox, oy, oz)

    Returns:
        Dict with keys 'position', 'rotation', 'scale', each a 3-tuple.
        Rotation is YXZ Euler angles in radians.
    """
    # Step 1: Extract position (last 3 values)
    position = (values[9], values[10], values[11])

    # Step 2: Reconstruct basis matrix (column-major → row-major)
    # Row i, Col j = values[j*3 + i] for the 3x3 part
    rows = [
        [values[0], values[3], values[6]],
        [values[1], values[4], values[7]],
        [values[2], values[5], values[8]],
    ]

    # Step 3: Clean floating-point noise
    for i in range(3):
        for j in range(3):
            if abs(rows[i][j]) < _NOISE_EPSILON:
                rows[i][j] = 0.0

    # Step 4: Extract scale with determinant sign check
    sx = math.sqrt(rows[0][0] ** 2 + rows[1][0] ** 2 + rows[2][0] ** 2)
    sy = math.sqrt(rows[0][1] ** 2 + rows[1][1] ** 2 + rows[2][1] ** 2)
    sz = math.sqrt(rows[0][2] ** 2 + rows[1][2] ** 2 + rows[2][2] ** 2)

    # Compute determinant
    det = (
        rows[0][0] * (rows[1][1] * rows[2][2] - rows[1][2] * rows[2][1])
        - rows[0][1] * (rows[1][0] * rows[2][2] - rows[1][2] * rows[2][0])
        + rows[0][2] * (rows[1][0] * rows[2][1] - rows[1][1] * rows[2][0])
    )

    if det < 0:
        sx = -sx

    scale = (sx, sy, sz)

    # Step 5: Normalize basis (divide each column by its scale)
    m = [[0.0] * 3 for _ in range(3)]
    for i in range(3):
        s_val = [sx, sy, sz][i]
        if abs(s_val) > _NOISE_EPSILON:
            for r in range(3):
                m[r][i] = rows[r][i] / s_val
        else:
            # Zero scale — treat as identity for this column
            m[i][i] = 1.0

    # Step 6: YXZ Euler decomposition (Godot's algorithm from basis.cpp)
    m12 = m[1][2]

    if abs(m12) < (1.0 - _GIMBAL_EPSILON):
        x = math.asin(-m12)
        y = math.atan2(m[0][2], m[2][2])
        z = math.atan2(m[1][0], m[1][1])
    else:
        # Gimbal lock
        z = 0.0
        if m12 < 0:
            x = math.pi / 2.0
            y = math.atan2(m[0][1], m[0][0])
        else:
            x = -math.pi / 2.0
            y = math.atan2(-m[0][1], m[0][0])

    # Step 7: Clean output angles
    if abs(x) < _ANGLE_EPSILON:
        x = 0.0
    if abs(y) < _ANGLE_EPSILON:
        y = 0.0
    if abs(z) < _ANGLE_EPSILON:
        z = 0.0

    rotation = (x, y, z)

    return {"position": position, "rotation": rotation, "scale": scale, "raw": values}


def _parse_array(s: str) -> list[object]:
    """Parse a TSCN array literal like [1, 2, 3] or ["a", "b"]."""
    s = s.strip()
    if not (s.startswith("[") and s.endswith("]")):
        return [s]

    inner = s[1:-1].strip()
    if not inner:
        return []

    parts = _split_at_depth_zero(inner, ",")
    return [parse_value(p.strip()) for p in parts if p.strip()]


def _parse_dict(s: str) -> dict[str, object]:
    """Parse a TSCN dictionary literal like {"key": value, ...}."""
    s = s.strip()
    if not (s.startswith("{") and s.endswith("}")):
        return {}

    inner = s[1:-1].strip()
    if not inner:
        return {}

    result: dict[str, object] = {}
    pairs = _split_at_depth_zero(inner, ",")

    for pair in pairs:
        pair = pair.strip()
        if not pair:
            continue

        # Find the colon separator (first : at depth 0)
        colon_parts = _split_at_depth_zero(pair, ":")
        if len(colon_parts) < 2:
            continue

        key_str = colon_parts[0].strip()
        val_str = ":".join(colon_parts[1:]).strip()

        # Parse key (usually a quoted string)
        key = parse_value(key_str)
        if not isinstance(key, str):
            key = str(key)

        result[key] = parse_value(val_str)

    return result


def _split_at_depth_zero(s: str, delimiter: str = ",") -> list[str]:
    """Split string by delimiter only when bracket/brace/paren depth is zero.

    Respects quoted strings (does not count brackets inside quotes).
    Uses index-based slicing instead of char-by-char append for performance.
    """
    parts: list[str] = []
    depth = 0
    in_string = False
    escape = False
    dlen = len(delimiter)
    slen = len(s)
    start = 0

    i = 0
    while i < slen:
        c = s[i]

        if escape:
            escape = False
            i += 1
            continue

        if c == "\\":
            escape = True
            i += 1
            continue

        if c == '"':
            in_string = not in_string
            i += 1
            continue

        if in_string:
            i += 1
            continue

        if c in "([{":
            depth += 1
            i += 1
            continue

        if c in ")]}":
            depth -= 1
            i += 1
            continue

        if depth == 0 and s[i:i + dlen] == delimiter:
            parts.append(s[start:i])
            i += dlen
            start = i
            continue

        i += 1

    parts.append(s[start:])
    return parts


def _unescape_string(s: str) -> str:
    """Handle basic escape sequences in TSCN strings."""
    return s.replace('\\"', '"').replace("\\n", "\n").replace("\\t", "\t").replace("\\\\", "\\")
