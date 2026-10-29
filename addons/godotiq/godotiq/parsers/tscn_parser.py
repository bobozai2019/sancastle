"""Parser for Godot .tscn scene files.

Extracts node hierarchy, transforms, resources, and signal connections
from Godot's text scene format.
"""

from __future__ import annotations

import enum
import logging
import os
import re
from dataclasses import dataclass, field

from godotiq.parsers.value_parser import decompose_transform3d, parse_value

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Dataclasses
# ---------------------------------------------------------------------------


@dataclass
class SceneHeader:
    """Parsed [gd_scene] header line."""

    format: int = 3
    load_steps: int | None = None
    uid: str | None = None


@dataclass
class ExtResource:
    """One [ext_resource] entry referencing an external file."""

    id: str = ""
    type: str = ""
    path: str = ""
    uid: str | None = None


@dataclass
class SubResource:
    """One [sub_resource] block with inline properties."""

    id: str = ""
    type: str = ""
    properties: dict[str, object] = field(default_factory=dict)


@dataclass
class Connection:
    """One [connection] signal wiring entry."""

    signal: str = ""
    from_node: str = ""
    to_node: str = ""
    method: str = ""
    flags: int = 0
    binds: list[object] = field(default_factory=list)


@dataclass
class TscnNode:
    """A single node in a Godot scene tree."""

    # Identity
    name: str = ""
    type: str = ""
    # Hierarchy
    parent: str = ""
    children: list[TscnNode] = field(default_factory=list)
    # Scene instancing
    instance: str | None = None
    unique_id: int | None = None
    is_instance_override: bool = False
    # Groups and script
    groups: list[str] = field(default_factory=list)
    script: str | None = None
    # Spatial (from Transform3D decomposition)
    position: tuple[float, float, float] | None = None
    rotation: tuple[float, float, float] | None = None
    scale: tuple[float, float, float] | None = None
    # Data
    properties: dict[str, object] = field(default_factory=dict)
    metadata: dict[str, object] = field(default_factory=dict)


@dataclass
class TscnScene:
    """Parsed representation of a .tscn file."""

    header: SceneHeader = field(default_factory=lambda: SceneHeader(format=3))
    ext_resources: dict[str, ExtResource] = field(default_factory=dict)
    sub_resources: dict[str, SubResource] = field(default_factory=dict)
    root: TscnNode | None = None
    nodes: list[TscnNode] = field(default_factory=list)
    connections: list[Connection] = field(default_factory=list)

    def find_node(self, path: str) -> TscnNode | None:
        """Find a node by slash-separated path from the root.

        Args:
            path: Node path like 'Building/LockedZones/Zone'.
                  Empty string or root node name returns root.

        Returns:
            The matching TscnNode, or None if not found.
        """
        if self.root is None:
            return None

        if not path or path == self.root.name:
            return self.root

        segments = path.split("/")
        # If path starts with root name, skip it
        if segments[0] == self.root.name:
            segments = segments[1:]

        current = self.root
        for seg in segments:
            found = None
            for child in current.children:
                if child.name == seg:
                    found = child
                    break
            if found is None:
                return None
            current = found
        return current

    def get_nodes_by_group(self, group: str) -> list[TscnNode]:
        """Return all nodes that belong to the given group."""
        return [n for n in self.nodes if group in n.groups]

    def get_nodes_by_type(self, type_name: str) -> list[TscnNode]:
        """Return all nodes of the given Godot type."""
        return [n for n in self.nodes if n.type == type_name]

    def get_all_scripts(self) -> list[str]:
        """Collect unique script resource paths from all nodes."""
        seen: set[str] = set()
        result: list[str] = []
        for node in self.nodes:
            if node.script is not None:
                resource = self.ext_resources.get(node.script)
                if resource is not None and resource.path not in seen:
                    seen.add(resource.path)
                    result.append(resource.path)
        return result

    def get_all_instances(self) -> list[str]:
        """Collect unique instanced scene resource paths from all nodes."""
        seen: set[str] = set()
        result: list[str] = []
        for node in self.nodes:
            if node.instance is not None:
                resource = self.ext_resources.get(node.instance)
                if resource is not None and resource.path not in seen:
                    seen.add(resource.path)
                    result.append(resource.path)
        return result


# ---------------------------------------------------------------------------
# State machine
# ---------------------------------------------------------------------------


class _ParserState(enum.Enum):
    INITIAL = "initial"
    FILE_HEADER = "file_header"
    EXT_RESOURCE = "ext_resource"
    SUB_RESOURCE = "sub_resource"
    NODE = "node"
    CONNECTION = "connection"
    EDITABLE = "editable"


_SECTION_TYPES = frozenset({
    "gd_scene", "gd_resource",
    "ext_resource", "sub_resource",
    "node", "connection", "editable",
})

# Regex for extracting header attributes
_HEADER_ATTR_RE = re.compile(
    r'(\w+)='
    r'('
    r'"[^"]*"'
    r'|\[[^\]]*\]'
    r'|\w+\([^)]*\)'
    r'|[^\s\]]*'
    r')'
)


def _is_section_header(line: str) -> str | None:
    """Return the section type if line is a section header, else None."""
    if not line.startswith("["):
        return None
    # Extract first word after [
    end = len(line)
    for i, c in enumerate(line[1:], 1):
        if c in (" ", "]"):
            end = i
            break
    word = line[1:end]
    if word in _SECTION_TYPES:
        return word
    return None


def _parse_header_attrs(line: str) -> dict[str, str]:
    """Extract key=value pairs from a section header line."""
    # Strip [ and ]
    inner = line.strip()
    if inner.startswith("["):
        inner = inner[1:]
    if inner.endswith("]"):
        inner = inner[:-1]

    attrs: dict[str, str] = {}
    for m in _HEADER_ATTR_RE.finditer(inner):
        key = m.group(1)
        val = m.group(2)
        # Strip quotes from string values
        if val.startswith('"') and val.endswith('"'):
            val = val[1:-1]
        attrs[key] = val
    return attrs


def _bracket_depth_change(text: str) -> int:
    """Return net bracket/brace/paren depth change, ignoring quoted content."""
    depth = 0
    in_string = False
    escape = False
    for c in text:
        if escape:
            escape = False
            continue
        if c == "\\":
            escape = True
            continue
        if c == '"':
            in_string = not in_string
            continue
        if in_string:
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
    return depth


def parse_tscn(path: str) -> TscnScene:
    """Parse a .tscn file from disk into a TscnScene.

    Args:
        path: Filesystem path to the .tscn file.

    Returns:
        Parsed scene representation with full node hierarchy.

    Raises:
        FileNotFoundError: If the file does not exist.
    """
    if not os.path.isfile(path):
        raise FileNotFoundError(f"Scene file not found: {path}")

    with open(path, encoding="utf-8") as f:
        lines = f.readlines()

    scene = TscnScene()
    state = _ParserState.INITIAL
    current_sub: SubResource | None = None
    current_node: TscnNode | None = None

    # Multiline accumulation
    accumulating = False
    accum_lines: list[str] = []
    accum_key = ""
    depth = 0

    for raw_line in lines:
        line = raw_line.rstrip("\n").rstrip("\r")

        # Skip blank lines and comments
        stripped = line.strip()
        if not stripped or stripped.startswith(";"):
            continue

        # --- Multiline accumulation ---
        if accumulating:
            sec_type = _is_section_header(stripped)
            if sec_type is not None:
                # New section header interrupts multiline value
                logger.warning(
                    "Unfinished multiline value for '%s', new section encountered",
                    accum_key,
                )
                accumulating = False
                accum_lines = []
                depth = 0
                # Fall through to process this header
            else:
                accum_lines.append(line)
                depth += _bracket_depth_change(line)
                if depth <= 0:
                    full_value = "\n".join(accum_lines)
                    # Store heavy sub_resource data as raw strings
                    # (_surfaces, blend_shape_data, etc. contain huge
                    # PackedByteArray blocks that are not useful to parse)
                    if accum_key.startswith("_") or accum_key in (
                        "blend_shapes", "surfaces",
                    ):
                        parsed: object = full_value
                    else:
                        parsed = parse_value(full_value)
                    _store_property(
                        state, accum_key, parsed,
                        current_sub, current_node,
                    )
                    accumulating = False
                    accum_lines = []
                    depth = 0
                continue

        # --- Section header detection ---
        sec_type = _is_section_header(stripped)
        if sec_type is not None:
            attrs = _parse_header_attrs(stripped)

            if sec_type == "gd_scene" or sec_type == "gd_resource":
                state = _ParserState.FILE_HEADER
                scene.header = SceneHeader(
                    format=int(attrs.get("format", "3")),
                    load_steps=int(attrs["load_steps"]) if "load_steps" in attrs else None,
                    uid=attrs.get("uid"),
                )

            elif sec_type == "ext_resource":
                state = _ParserState.EXT_RESOURCE
                res_id = attrs.get("id", "")
                ext = ExtResource(
                    id=res_id,
                    type=attrs.get("type", ""),
                    path=attrs.get("path", ""),
                    uid=attrs.get("uid"),
                )
                scene.ext_resources[res_id] = ext

            elif sec_type == "sub_resource":
                state = _ParserState.SUB_RESOURCE
                sub_id = attrs.get("id", "")
                current_sub = SubResource(
                    id=sub_id,
                    type=attrs.get("type", ""),
                )
                scene.sub_resources[sub_id] = current_sub

            elif sec_type == "node":
                state = _ParserState.NODE
                # Parse groups from header
                groups: list[str] = []
                if "groups" in attrs:
                    parsed_groups = parse_value(attrs["groups"])
                    if isinstance(parsed_groups, list):
                        groups = [str(g) for g in parsed_groups]

                # Parse instance from header
                instance_id: str | None = None
                if "instance" in attrs:
                    inst_val = parse_value(attrs["instance"])
                    if isinstance(inst_val, dict) and inst_val.get("type") == "ext_resource":
                        instance_id = inst_val["id"]
                    elif isinstance(inst_val, str):
                        instance_id = inst_val

                # Parse unique_id
                unique_id: int | None = None
                if "unique_name_in_owner" in attrs:
                    try:
                        unique_id = int(attrs["unique_name_in_owner"])
                    except ValueError:
                        pass

                current_node = TscnNode(
                    name=attrs.get("name", ""),
                    type=attrs.get("type", ""),
                    parent=attrs.get("parent", ""),
                    instance=instance_id,
                    unique_id=unique_id,
                    groups=groups,
                )
                scene.nodes.append(current_node)

            elif sec_type == "connection":
                state = _ParserState.CONNECTION
                flags = 0
                if "flags" in attrs:
                    try:
                        flags = int(attrs["flags"])
                    except ValueError:
                        pass
                conn = Connection(
                    signal=attrs.get("signal", ""),
                    from_node=attrs.get("from", ""),
                    to_node=attrs.get("to", ""),
                    method=attrs.get("method", ""),
                    flags=flags,
                )
                scene.connections.append(conn)

            elif sec_type == "editable":
                state = _ParserState.EDITABLE

            continue

        # --- Property line ---
        if " = " not in stripped:
            continue

        key, _, value_str = stripped.partition(" = ")
        key = key.strip()
        value_str = value_str.strip()

        # Check for multiline value
        line_depth = _bracket_depth_change(value_str)
        if line_depth > 0:
            accumulating = True
            accum_lines = [value_str]
            accum_key = key
            depth = line_depth
            continue

        # Parse and store single-line value
        parsed = parse_value(value_str)
        _store_property(state, key, parsed, current_sub, current_node)

    # --- Pass 2: Tree reconstruction ---
    _build_tree(scene)

    return scene


def _store_property(
    state: _ParserState,
    key: str,
    value: object,
    current_sub: SubResource | None,
    current_node: TscnNode | None,
) -> None:
    """Store a parsed property value on the appropriate data structure."""
    if state == _ParserState.SUB_RESOURCE and current_sub is not None:
        current_sub.properties[key] = value

    elif state == _ParserState.NODE and current_node is not None:
        if key == "script":
            if isinstance(value, dict) and value.get("type") == "ext_resource":
                current_node.script = value["id"]
            elif isinstance(value, str):
                current_node.script = value

        elif key == "transform":
            if isinstance(value, dict) and "position" in value:
                current_node.position = value["position"]
                current_node.rotation = value["rotation"]
                current_node.scale = value["scale"]
            current_node.properties[key] = value

        elif key.startswith("metadata/"):
            meta_key = key[len("metadata/"):]
            current_node.metadata[meta_key] = value

        else:
            current_node.properties[key] = value


def _build_tree(scene: TscnScene) -> None:
    """Reconstruct parent-child hierarchy from flat node list (Pass 2)."""
    if not scene.nodes:
        return

    # Find root (node with empty parent)
    root: TscnNode | None = None
    for node in scene.nodes:
        if node.parent == "":
            root = node
            break

    if root is None:
        logger.warning("No root node found (no node without parent attribute)")
        return

    scene.root = root

    # Build path → node lookup
    path_map: dict[str, TscnNode] = {}
    root_name = root.name
    path_map[root_name] = root

    for node in scene.nodes:
        if node is root:
            continue
        if node.parent == ".":
            full_path = f"{root_name}/{node.name}"
        else:
            full_path = f"{root_name}/{node.parent}/{node.name}"
        path_map[full_path] = node

    # Collect names of instance nodes (nodes with instance=ExtResource(...))
    instance_names: set[str] = set()
    for node in scene.nodes:
        if node.instance is not None:
            instance_names.add(node.name)

    # Link children to parents
    for node in scene.nodes:
        if node is root:
            continue
        if node.parent == ".":
            parent_path = root_name
        else:
            parent_path = f"{root_name}/{node.parent}"

        parent_node = path_map.get(parent_path)
        if parent_node is not None:
            parent_node.children.append(node)
        else:
            # Check if this is a property override on an instanced scene.
            # In .tscn files, nodes inside instanced scenes appear with parent
            # paths relative to the instance root (e.g. parent="Geometry" when
            # the instance node "Map" contains a child "Geometry"). The first
            # segment of the parent path (or node.parent itself for direct
            # children) corresponds to the instance node name.
            first_segment = node.parent.split("/")[0] if node.parent != "." else ""
            instance_parent = path_map.get(f"{root_name}/{first_segment}")
            if first_segment in instance_names and instance_parent is not None:
                node.is_instance_override = True
                instance_parent.children.append(node)
            else:
                logger.warning(
                    "Parent not found for node '%s' (parent path: '%s')",
                    node.name, node.parent,
                )
