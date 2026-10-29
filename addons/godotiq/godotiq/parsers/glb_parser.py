"""GLB/glTF bounding box extraction from JSON metadata."""

from __future__ import annotations

import json
import struct
from pathlib import Path

_GLB_MAGIC = 0x46546C67  # "glTF"
_JSON_CHUNK_TYPE = 0x4E4F534A  # "JSON"


def extract_glb_bounds(file_path: str) -> dict | None:
    """Extract axis-aligned bounding box from a GLB/glTF file.

    For GLB: reads only the JSON chunk (no binary parsing).
    For glTF: reads the JSON file directly.
    Returns the union of all mesh primitive POSITION accessor min/max values.

    Note: bounds are in accessor local space. For multi-mesh assets with node
    transforms, the actual world-space bounds may differ.

    Args:
        file_path: Absolute filesystem path to a .glb or .gltf file.

    Returns:
        {"min": [x, y, z], "max": [x, y, z], "size": [sx, sy, sz]} or None
        if parsing fails.
    """
    try:
        p = Path(file_path)
        suffix = p.suffix.lower()
        if suffix == ".glb":
            gltf_json = _parse_glb_json(p)
        elif suffix == ".gltf":
            gltf_json = _parse_gltf_json(p)
        else:
            return None
        if gltf_json is None:
            return None
        return _extract_bounds_from_json(gltf_json)
    except Exception:
        return None


def _parse_glb_json(path: Path) -> dict | None:
    """Read and return the JSON chunk from a GLB file."""
    with path.open("rb") as f:
        header = f.read(12)
        if len(header) < 12:
            return None
        magic, _version, _total_length = struct.unpack("<III", header)
        if magic != _GLB_MAGIC:
            return None
        chunk_header = f.read(8)
        if len(chunk_header) < 8:
            return None
        chunk_length, chunk_type = struct.unpack("<II", chunk_header)
        if chunk_type != _JSON_CHUNK_TYPE:
            return None
        json_data = f.read(chunk_length)
        if len(json_data) < chunk_length:
            return None
        return json.loads(json_data)


def _parse_gltf_json(path: Path) -> dict | None:
    """Read and return JSON from a plain .gltf file."""
    text = path.read_text(encoding="utf-8")
    result = json.loads(text)
    if not isinstance(result, dict):
        return None
    return result


def _extract_bounds_from_json(gltf: dict) -> dict | None:
    """Walk meshes/primitives/accessors to compute the union bounding box."""
    meshes = gltf.get("meshes")
    if not meshes:
        return None
    accessors = gltf.get("accessors", [])

    all_mins: list[list[float]] = []
    all_maxs: list[list[float]] = []

    for mesh in meshes:
        for prim in mesh.get("primitives", []):
            attrs = prim.get("attributes", {})
            pos_idx = attrs.get("POSITION")
            if pos_idx is None:
                continue
            if pos_idx < 0 or pos_idx >= len(accessors):
                continue
            acc = accessors[pos_idx]
            acc_min = acc.get("min")
            acc_max = acc.get("max")
            if (
                not acc_min
                or not acc_max
                or len(acc_min) < 3
                or len(acc_max) < 3
            ):
                continue
            all_mins.append(acc_min[:3])
            all_maxs.append(acc_max[:3])

    if not all_mins:
        return None

    union_min = [
        min(m[i] for m in all_mins) for i in range(3)
    ]
    union_max = [
        max(m[i] for m in all_maxs) for i in range(3)
    ]
    size = [union_max[i] - union_min[i] for i in range(3)]

    return {"min": union_min, "max": union_max, "size": size}
