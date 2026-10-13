"""Scene resolver for recursive instance expansion.

Takes a parsed TscnScene and resolves all instance references by parsing
and inlining the referenced .tscn files, producing a fully expanded node tree.
"""

from __future__ import annotations

import logging
import math
from dataclasses import dataclass, field
from pathlib import Path

from godotiq.parsers.tscn_parser import ExtResource, TscnNode, TscnScene, parse_tscn
from godotiq.parsers.value_parser import decompose_transform3d

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Dataclasses
# ---------------------------------------------------------------------------


@dataclass
class ResolvedScene:
    """Result of expanding all instances in a parsed scene."""

    source_path: str
    """Original .tscn file path (res:// or filesystem)."""

    root: TscnNode
    """Root node with all instances expanded as children."""

    total_nodes: int
    """Total node count after expansion."""

    instance_sources: dict[str, str]
    """Maps node full_path -> source res:// path for instanced nodes."""

    unresolved: list[str]
    """res:// paths of scenes that couldn't be found or failed to parse."""


@dataclass
class WorldNode:
    """A node with its computed world-space transform."""

    node: TscnNode
    """Reference to the original node."""

    world_position: tuple[float, float, float]
    world_rotation: tuple[float, float, float]
    """YXZ Euler angles in radians."""

    world_scale: tuple[float, float, float]

    full_path: str
    """Slash-separated path from root."""

    depth: int
    """Nesting level (root=0)."""

    is_instance_root: bool
    """True if this node was created by expanding an instance."""

    instance_source: str | None
    """Source res:// path if is_instance_root."""


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def resolve_scene(
    scene: TscnScene,
    project_root: Path,
    max_depth: int = 10,
) -> ResolvedScene:
    """Resolve all instances in a parsed scene.

    Args:
        scene: A TscnScene from parse_tscn().
        project_root: The directory containing project.godot.
        max_depth: Maximum recursion depth for nested instances.

    Returns:
        ResolvedScene with fully expanded node tree.
    """
    if scene.root is None:
        return ResolvedScene(
            source_path="",
            root=TscnNode(name="Empty"),
            total_nodes=0,
            instance_sources={},
            unresolved=[],
        )

    instance_sources: dict[str, str] = {}
    unresolved: list[str] = []
    parse_cache: dict[str, TscnScene] = {}

    cloned_root = _clone_node(scene.root)

    def _resolve_nodes(
        node: TscnNode,
        ext_resources: dict[str, ExtResource],
        depth: int,
        active_paths: set[str],
        parent_full_path: str,
    ) -> None:
        for child in node.children:
            child_path = (
                f"{parent_full_path}/{child.name}" if parent_full_path else child.name
            )

            if child.instance is not None:
                ext_id = child.instance
                ext_res = ext_resources.get(ext_id)

                if ext_res is None:
                    logger.warning(
                        "ExtResource ID %r not found in ext_resources", ext_id
                    )
                    continue

                res_path = ext_res.path
                instance_sources[child_path] = res_path

                # Non-.tscn instances: record but don't expand
                if not res_path.endswith(".tscn"):
                    continue

                # Cycle detection
                if res_path in active_paths:
                    logger.warning("Cycle detected: %s", res_path)
                    unresolved.append(res_path)
                    continue

                # Depth check
                if depth >= max_depth:
                    logger.warning(
                        "Max depth %d reached, skipping %s", max_depth, res_path
                    )
                    continue

                # Resolve filesystem path
                fs_path = _resolve_res_path(res_path, project_root)

                if not fs_path.exists():
                    logger.warning("Instance file not found: %s", fs_path)
                    unresolved.append(res_path)
                    continue

                # Parse (with cache)
                fs_key = str(fs_path)
                if fs_key not in parse_cache:
                    try:
                        parse_cache[fs_key] = parse_tscn(fs_key)
                    except Exception:
                        logger.exception("Failed to parse %s", fs_key)
                        unresolved.append(res_path)
                        continue

                instanced_scene = parse_cache[fs_key]

                if instanced_scene.root is None:
                    unresolved.append(res_path)
                    continue

                cloned_inst_root = _clone_node(instanced_scene.root)

                # Apply property overrides
                _apply_overrides(child, cloned_inst_root)

                # Copy type if empty
                if not child.type:
                    child.type = cloned_inst_root.type

                # Graft children
                child.children = cloned_inst_root.children

                # Recurse into instanced children with instanced scene's ext_resources
                _resolve_nodes(
                    child,
                    instanced_scene.ext_resources,
                    depth + 1,
                    active_paths | {res_path},
                    child_path,
                )
            else:
                # Non-instance node: still recurse for nested instances
                _resolve_nodes(
                    child,
                    ext_resources,
                    depth,
                    active_paths,
                    child_path,
                )

    _resolve_nodes(cloned_root, scene.ext_resources, 0, set(), "")

    total = _count_nodes(cloned_root)

    return ResolvedScene(
        source_path=getattr(scene.header, "uid", "") or "",
        root=cloned_root,
        total_nodes=total,
        instance_sources=instance_sources,
        unresolved=unresolved,
    )


def calculate_world_transforms(resolved: ResolvedScene) -> list[WorldNode]:
    """Compute world-space transforms for every node in the resolved scene.

    Uses depth-first traversal composing parent transforms with child local
    transforms using raw basis matrix math (no Euler composition).

    Args:
        resolved: A ResolvedScene from resolve_scene().

    Returns:
        Flat list of WorldNode in depth-first order.
    """
    _IDENTITY_BASIS = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
    _IDENTITY_ORIGIN = (0.0, 0.0, 0.0)
    identity = (_IDENTITY_BASIS, _IDENTITY_ORIGIN)

    result: list[WorldNode] = []

    def _walk(
        node: TscnNode,
        parent_transform: tuple,
        parent_path: str,
        depth: int,
    ) -> None:
        local = _get_local_transform(node)
        world = _compose_transforms(parent_transform, local)

        world_basis, world_origin = world

        # Decompose world transform for output
        raw = (
            world_basis[0][0], world_basis[0][1], world_basis[0][2],
            world_basis[1][0], world_basis[1][1], world_basis[1][2],
            world_basis[2][0], world_basis[2][1], world_basis[2][2],
            world_origin[0], world_origin[1], world_origin[2],
        )
        decomposed = decompose_transform3d(raw)

        if depth == 0:
            full_path = ""
        elif parent_path == "":
            full_path = node.name
        else:
            full_path = f"{parent_path}/{node.name}"

        is_inst = full_path in resolved.instance_sources
        inst_src = resolved.instance_sources.get(full_path)

        wn = WorldNode(
            node=node,
            world_position=decomposed["position"],
            world_rotation=decomposed["rotation"],
            world_scale=decomposed["scale"],
            full_path=full_path,
            depth=depth,
            is_instance_root=is_inst,
            instance_source=inst_src,
        )
        result.append(wn)

        for child in node.children:
            _walk(child, world, full_path, depth + 1)

    _walk(resolved.root, identity, "", 0)
    return result


def find_nodes_by_type(world_nodes: list[WorldNode], node_type: str) -> list[WorldNode]:
    """Return all WorldNodes whose node.type matches the given type."""
    return [wn for wn in world_nodes if wn.node.type == node_type]


def find_nodes_by_group(world_nodes: list[WorldNode], group: str) -> list[WorldNode]:
    """Return all WorldNodes whose node.groups contains the given group."""
    return [wn for wn in world_nodes if group in wn.node.groups]


def find_nodes_in_radius(
    world_nodes: list[WorldNode],
    center: tuple[float, float, float],
    radius: float,
) -> list[WorldNode]:
    """Return all WorldNodes within Euclidean distance radius from center."""
    r_sq = radius * radius
    cx, cy, cz = center
    result = []
    for wn in world_nodes:
        wx, wy, wz = wn.world_position
        dist_sq = (wx - cx) ** 2 + (wy - cy) ** 2 + (wz - cz) ** 2
        if dist_sq <= r_sq:
            result.append(wn)
    return result


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _resolve_res_path(res_path: str, project_root: Path) -> Path:
    """Convert res://x/y/z.tscn to project_root/x/y/z.tscn."""
    return project_root / res_path[6:]


def _clone_node(node: TscnNode) -> TscnNode:
    """Create a deep copy of a TscnNode and all its children."""
    return TscnNode(
        name=node.name,
        type=node.type,
        parent=node.parent,
        children=[_clone_node(c) for c in node.children],
        instance=node.instance,
        unique_id=node.unique_id,
        groups=list(node.groups),
        script=node.script,
        position=node.position,
        rotation=node.rotation,
        scale=node.scale,
        properties=dict(node.properties),
        metadata=dict(node.metadata),
    )


def _apply_overrides(instance_node: TscnNode, cloned_root: TscnNode) -> None:
    """Apply property overrides from instance node onto cloned instanced root."""
    # Copy all properties
    for key, value in instance_node.properties.items():
        cloned_root.properties[key] = value

    # Handle transform specially
    if "transform" in instance_node.properties:
        cloned_root.position = instance_node.position
        cloned_root.rotation = instance_node.rotation
        cloned_root.scale = instance_node.scale

    # Handle script
    if instance_node.script is not None:
        cloned_root.script = instance_node.script

    # Handle groups (extend, not replace)
    cloned_root.groups.extend(instance_node.groups)

    # Handle metadata
    cloned_root.metadata.update(instance_node.metadata)


def _get_local_transform(node: TscnNode) -> tuple:
    """Extract local transform from a node as (basis_columns, origin).

    Uses the 'raw' key from the transform property when available.
    Falls back to identity if no transform property exists.
    """
    _IDENTITY_BASIS = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
    _IDENTITY_ORIGIN = (0.0, 0.0, 0.0)

    transform = node.properties.get("transform")
    if transform is None or not isinstance(transform, dict):
        return (_IDENTITY_BASIS, _IDENTITY_ORIGIN)

    raw = transform.get("raw")
    if raw is not None and len(raw) == 12:
        col0 = (raw[0], raw[1], raw[2])
        col1 = (raw[3], raw[4], raw[5])
        col2 = (raw[6], raw[7], raw[8])
        origin = (raw[9], raw[10], raw[11])
        return ((col0, col1, col2), origin)

    # Fallback: use decomposed position (no rotation reconstruction)
    pos = node.position or _IDENTITY_ORIGIN
    return (_IDENTITY_BASIS, pos)


def _basis_multiply(
    a: tuple[tuple[float, ...], ...],
    b: tuple[tuple[float, ...], ...],
) -> tuple[tuple[float, ...], ...]:
    """Multiply two 3x3 basis matrices (column-major representation).

    Each basis is a tuple of 3 column vectors.
    Result[col_j] = a.xform(b[col_j]).
    """
    return (
        _basis_xform(a, b[0]),
        _basis_xform(a, b[1]),
        _basis_xform(a, b[2]),
    )


def _basis_xform(
    basis: tuple[tuple[float, ...], ...],
    point: tuple[float, ...],
) -> tuple[float, float, float]:
    """Transform a point by a basis: col0*x + col1*y + col2*z."""
    col0, col1, col2 = basis
    x, y, z = point[0], point[1], point[2]
    return (
        col0[0] * x + col1[0] * y + col2[0] * z,
        col0[1] * x + col1[1] * y + col2[1] * z,
        col0[2] * x + col1[2] * y + col2[2] * z,
    )


def _compose_transforms(parent: tuple, child: tuple) -> tuple:
    """Compose parent and child transforms.

    child_world.origin = parent.basis.xform(child_local.origin) + parent.origin
    child_world.basis  = parent.basis * child_local.basis
    """
    p_basis, p_origin = parent
    c_basis, c_origin = child

    world_origin_raw = _basis_xform(p_basis, c_origin)
    world_origin = (
        world_origin_raw[0] + p_origin[0],
        world_origin_raw[1] + p_origin[1],
        world_origin_raw[2] + p_origin[2],
    )
    world_basis = _basis_multiply(p_basis, c_basis)
    return (world_basis, world_origin)


def _count_nodes(node: TscnNode) -> int:
    """Count total nodes in a tree."""
    return 1 + sum(_count_nodes(c) for c in node.children)
