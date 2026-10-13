"""Spatial validation for node_ops.

Uses scene_map data (Phase 1 filesystem analysis) to validate
proposed node operations before execution.

Checks:
- Proximity to walls (StaticBody3D nodes)
- Overlap with existing nodes
- Distance from similar siblings (outlier detection)
- Scale outlier detection
"""

from __future__ import annotations

import math

# Thresholds (meters)
WALL_BLOCKED_DISTANCE = 0.2
WALL_WARNING_DISTANCE = 0.5
WALL_Y_SKIP_THRESHOLD = 3.0
OVERLAP_DISTANCE = 0.05
SIBLING_OUTLIER_FACTOR = 3.0
SIBLING_MIN_DISTANCE = 5.0
SCALE_OUTLIER_FACTOR = 3.0
NAME_SUFFIX_MAX_LEN = 3

_SEVERITY_PRIORITY = {"OK": 0, "WARNING": 1, "BLOCKED": 2}
_WALL_NAME_KEYWORDS = ("wall", "floor", "ceiling", "ground", "barrier")


def _extract_nodes(scene_data: dict) -> list[dict]:
    """Extract the nodes list from scene_data dict. Returns [] if missing/empty."""
    return scene_data.get("nodes", [])


def _get_name_prefix(name: str) -> str:
    """Extract naming prefix for sibling detection.

    Finds the last underscore; if the suffix after it is 1-3 chars, returns
    everything up to and including the underscore. Otherwise returns "".
    """
    idx = name.rfind("_")
    if idx < 0:
        return ""
    suffix = name[idx + 1 :]
    if 1 <= len(suffix) <= NAME_SUFFIX_MAX_LEN:
        return name[: idx + 1]
    return ""


def _is_wall(node: dict) -> bool:
    """Check if a node represents a wall/boundary."""
    node_type = node.get("type", "").lower()
    if "staticbody" in node_type:
        return True
    node_name = node.get("name", "").lower()
    return any(kw in node_name for kw in _WALL_NAME_KEYWORDS)


def _dist_xz(x1: float, z1: float, x2: float, z2: float) -> float:
    return math.sqrt((x2 - x1) ** 2 + (z2 - z1) ** 2)


def _dist_3d(p1: list[float], p2: list[float]) -> float:
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(p1[:3], p2[:3])))


def _result(
    severity: str,
    message: str,
    checks: list[dict] | None = None,
    suggestion: dict | None = None,
) -> dict:
    return {
        "valid": severity != "BLOCKED",
        "severity": severity,
        "message": message,
        "suggestion": suggestion,
        "checks": checks or [],
    }


def _worst(a: str, b: str) -> str:
    return a if _SEVERITY_PRIORITY[a] >= _SEVERITY_PRIORITY[b] else b


# ---------------------------------------------------------------------------
# validate_move
# ---------------------------------------------------------------------------


def validate_move(
    target_position: list[float], node_name: str, scene_data: dict
) -> dict:
    """Validate a move operation against spatial context."""
    if len(target_position) < 3:
        return _result("BLOCKED", "Invalid position: need [x, y, z]")

    tx, ty, tz = target_position[0], target_position[1], target_position[2]
    nodes = _extract_nodes(scene_data)
    if not nodes:
        return _result(
            "OK",
            "No spatial data available — executing without validation",
            checks=[{"check": "data", "severity": "OK", "detail": "No scene_map data"}],
        )

    checks: list[dict] = []
    worst_severity = "OK"

    # Check 1: Wall proximity (XZ distance, skip if Y diff > threshold)
    wall_check = _check_wall_distance(tx, ty, tz, nodes, node_name)
    checks.append(wall_check)
    worst_severity = _worst(worst_severity, wall_check["severity"])

    # Check 2: Overlap (3D distance, same depth only)
    overlap_check = _check_overlap(tx, ty, tz, nodes, node_name)
    checks.append(overlap_check)
    worst_severity = _worst(worst_severity, overlap_check["severity"])

    # Check 3: Sibling outlier distance
    sibling_check = _check_sibling_distance(tx, ty, tz, node_name, nodes)
    checks.append(sibling_check)
    worst_severity = _worst(worst_severity, sibling_check["severity"])

    details = "; ".join(c["detail"] for c in checks)
    message = f"Position [{tx}, {ty}, {tz}]: {details}"
    return _result(worst_severity, message, checks=checks)


def _check_wall_distance(
    tx: float, ty: float, tz: float, nodes: list[dict], self_name: str
) -> dict:
    nearest_wall = None
    nearest_dist = float("inf")

    for n in nodes:
        if n.get("name") == self_name:
            continue
        if not _is_wall(n):
            continue
        pos = n.get("position", [0, 0, 0])
        if abs(pos[1] - ty) > WALL_Y_SKIP_THRESHOLD:
            continue
        d = _dist_xz(tx, tz, pos[0], pos[2])
        if d < nearest_dist:
            nearest_dist = d
            nearest_wall = n.get("name", "?")

    if nearest_wall is None:
        return {"check": "wall_distance", "severity": "OK", "detail": "No walls nearby"}

    if nearest_dist < WALL_BLOCKED_DISTANCE:
        return {
            "check": "wall_distance",
            "severity": "BLOCKED",
            "detail": f"{nearest_dist:.2f}m from wall {nearest_wall} (min {WALL_BLOCKED_DISTANCE}m)",
        }
    if nearest_dist < WALL_WARNING_DISTANCE:
        return {
            "check": "wall_distance",
            "severity": "WARNING",
            "detail": f"{nearest_dist:.2f}m from wall {nearest_wall} (warn < {WALL_WARNING_DISTANCE}m)",
        }
    return {
        "check": "wall_distance",
        "severity": "OK",
        "detail": f"{nearest_dist:.2f}m from nearest wall ({nearest_wall})",
    }


def _check_overlap(
    tx: float, ty: float, tz: float, nodes: list[dict], self_name: str
) -> dict:
    target_pos = [tx, ty, tz]
    # We need to determine target's depth for filtering.
    # Since the node being moved may not yet exist in the scene, we infer depth
    # by looking at the self node if present; otherwise skip depth filtering.
    self_depth = None
    for n in nodes:
        if n.get("name") == self_name and "depth" in n:
            self_depth = n["depth"]
            break

    nearest_overlap_name = None
    nearest_overlap_dist = float("inf")

    for n in nodes:
        if n.get("name") == self_name:
            continue
        # Depth filtering: only compare same-depth nodes
        if self_depth is not None and "depth" in n and n["depth"] != self_depth:
            continue
        pos = n.get("position", [0, 0, 0])
        d = _dist_3d(target_pos, pos)
        if d < nearest_overlap_dist:
            nearest_overlap_dist = d
            nearest_overlap_name = n.get("name", "?")

    if nearest_overlap_name is None:
        return {"check": "overlap", "severity": "OK", "detail": "No overlapping nodes"}

    if nearest_overlap_dist < OVERLAP_DISTANCE:
        return {
            "check": "overlap",
            "severity": "BLOCKED",
            "detail": f"Overlap with {nearest_overlap_name} ({nearest_overlap_dist:.3f}m apart)",
        }
    return {"check": "overlap", "severity": "OK", "detail": "No overlapping nodes"}


def _check_sibling_distance(
    tx: float, ty: float, tz: float, node_name: str, nodes: list[dict]
) -> dict:
    prefix = _get_name_prefix(node_name)
    if not prefix:
        return {"check": "sibling_distance", "severity": "OK", "detail": "No sibling prefix"}

    siblings = [
        n for n in nodes if n.get("name") != node_name and _get_name_prefix(n.get("name", "")) == prefix
    ]
    if len(siblings) < 2:
        return {"check": "sibling_distance", "severity": "OK", "detail": "Too few siblings to compare"}

    # Average pairwise distance among siblings
    total = 0.0
    count = 0
    for i, a in enumerate(siblings):
        for b in siblings[i + 1 :]:
            total += _dist_3d(a.get("position", [0, 0, 0]), b.get("position", [0, 0, 0]))
            count += 1
    avg_dist = total / count if count > 0 else 0

    target_pos = [tx, ty, tz]
    nearest_sibling_dist = float("inf")
    nearest_sibling_name = ""
    for s in siblings:
        d = _dist_3d(target_pos, s.get("position", [0, 0, 0]))
        if d < nearest_sibling_dist:
            nearest_sibling_dist = d
            nearest_sibling_name = s.get("name", "?")

    if (
        nearest_sibling_dist > SIBLING_OUTLIER_FACTOR * avg_dist
        and nearest_sibling_dist > SIBLING_MIN_DISTANCE
    ):
        return {
            "check": "sibling_distance",
            "severity": "WARNING",
            "detail": (
                f"{nearest_sibling_dist:.1f}m from nearest sibling {nearest_sibling_name} "
                f"(avg inter-sibling {avg_dist:.1f}m)"
            ),
        }
    return {
        "check": "sibling_distance",
        "severity": "OK",
        "detail": f"{nearest_sibling_dist:.1f}m from nearest sibling {nearest_sibling_name}",
    }


# ---------------------------------------------------------------------------
# validate_scale
# ---------------------------------------------------------------------------


def validate_scale(
    target_scale: list[float], node_name: str, scene_data: dict
) -> dict:
    """Validate a scale operation against similar nodes in the scene."""
    if len(target_scale) < 3:
        return _result("BLOCKED", "Invalid scale: need [x, y, z]")

    sx = target_scale[0]
    nodes = _extract_nodes(scene_data)
    prefix = _get_name_prefix(node_name)

    if not prefix:
        return _result("OK", f"Scale [{target_scale[0]},{target_scale[1]},{target_scale[2]}] — no siblings to compare")

    siblings = [
        n
        for n in nodes
        if n.get("name") != node_name
        and _get_name_prefix(n.get("name", "")) == prefix
        and "scale" in n
        and len(n["scale"]) >= 1
    ]

    if len(siblings) < 2:
        return _result("OK", f"Scale [{target_scale[0]},{target_scale[1]},{target_scale[2]}] — too few siblings")

    avg_scale = sum(s["scale"][0] for s in siblings) / len(siblings)
    if abs(avg_scale) < 0.001:
        return _result("OK", "Sibling scale near zero — skipping check")

    ratio = sx / avg_scale
    abs_ratio = abs(ratio)
    if abs_ratio > SCALE_OUTLIER_FACTOR or (abs_ratio > 0 and abs_ratio < 1.0 / SCALE_OUTLIER_FACTOR):
        return _result(
            "WARNING",
            f"Scale {sx:.3f} is {ratio:.1f}x vs avg {avg_scale:.3f} of similar nodes",
            checks=[
                {
                    "check": "scale_outlier",
                    "severity": "WARNING",
                    "detail": f"Scale {sx:.3f} is {ratio:.1f}x vs avg {avg_scale:.3f}",
                }
            ],
        )

    return _result(
        "OK",
        f"Scale [{target_scale[0]},{target_scale[1]},{target_scale[2]}] consistent with scene",
        checks=[
            {"check": "scale_outlier", "severity": "OK", "detail": "Scale consistent with siblings"}
        ],
    )
