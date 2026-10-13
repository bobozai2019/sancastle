"""Animation Intelligence tools -- animation data extraction and analysis.

These tools provide complete animation understanding for Godot 4 projects,
extracting data from inline .tscn animations, code-referenced GLB animations,
.tres resources, and AnimationTree state machines.
"""

from __future__ import annotations

import re
from collections import defaultdict

from mcp.server.fastmcp import Context

from godotiq.license import pro_unavailable_response
from godotiq.parsers.tscn_parser import TscnScene
from godotiq.pro_loader import get_pro_implementation
from godotiq.session import GodotIQSession

# ---------------------------------------------------------------------------
# Compiled regex patterns for GDScript analysis
# ---------------------------------------------------------------------------
_RE_PLAY = re.compile(r'\.play\(\s*(?:&)?"([^"]+)"')
_RE_QUEUE = re.compile(r'\.queue\(\s*(?:&)?"([^"]+)"')
_RE_TRAVEL = re.compile(r'\.travel\(\s*(?:&)?"([^"]+)"')
_RE_ANIM_PLAYER_VAR = re.compile(
    r'(?:var|@onready\s+var)\s+(\w+)\s*[:=].*AnimationPlayer'
)
_RE_ANIM_TREE_VAR = re.compile(
    r'(?:var|@onready\s+var)\s+(\w+)\s*[:=].*AnimationTree'
)
_RE_DICT_DECL = re.compile(r'(?:const|var)\s+(\w+)\s*:?=?\s*\{')
_RE_ARRAY_DECL = re.compile(r'(?:const|var)\s+(\w+)\s*:?=?\s*\[')
_RE_KV_PAIR = re.compile(r'"([^"]+)"\s*:\s*"([^"]+)"')
_RE_QUOTED_STR = re.compile(r'"([^"]+)"')
_RE_TRACK_TYPE = re.compile(r'^tracks/(\d+)/type$')
_RE_STRINGNAME = re.compile(r'^&"(.+)"$')
_RE_LIB_DATA = re.compile(r'"([^"]+)":\s*SubResource\("([^"]+)"\)')
_RE_STATE_NODE = re.compile(r'^states/([^/]+)/node$')

# Heuristic keywords for animation-related dict/array names
_ANIM_NAME_KEYWORDS = {"anim", "animation", "motion", "clip"}


# ---------------------------------------------------------------------------
# 2.0  _strip_string_name
# ---------------------------------------------------------------------------

def _strip_string_name(value: object) -> object:
    """Strip Godot StringName syntax (&\"name\") from a value.

    Args:
        value: Any value; only strings are processed.

    Returns:
        The unwrapped string if it matched &\"...\", otherwise the original value.
    """
    if not isinstance(value, str):
        return value
    m = _RE_STRINGNAME.match(value)
    if m:
        return m.group(1)
    return value


# ---------------------------------------------------------------------------
# 2.1  _extract_tscn_animations
# ---------------------------------------------------------------------------

def _extract_tscn_animations(scene: TscnScene) -> list[dict]:
    """Extract inline Animation sub_resources from a parsed scene.

    Args:
        scene: A parsed TscnScene object.

    Returns:
        List of animation info dicts with name, length, loop_mode,
        track_count, tracks_by_type, track_paths, sub_resource_id, source.
    """
    loop_mode_map = {0: "none", 1: "linear", 2: "pingpong"}
    results: list[dict] = []

    for sub_id, sub in scene.sub_resources.items():
        if sub.type != "Animation":
            continue

        name = sub.properties.get("resource_name", "")
        name = str(_strip_string_name(name)) if name else sub_id

        length = float(sub.properties.get("length", 1.0))
        loop_raw = sub.properties.get("loop_mode", 0)
        loop_mode = loop_mode_map.get(int(loop_raw), "none")

        # Count and categorize tracks
        tracks_by_type: dict[str, int] = defaultdict(int)
        track_paths: list[str] = []
        track_indices: set[int] = set()

        for key in sub.properties:
            m = _RE_TRACK_TYPE.match(key)
            if m:
                idx = int(m.group(1))
                track_indices.add(idx)
                track_type = str(sub.properties[key])
                tracks_by_type[track_type] += 1

        for idx in sorted(track_indices):
            path_key = f"tracks/{idx}/path"
            if path_key in sub.properties:
                track_paths.append(str(sub.properties[path_key]))

        results.append({
            "name": name,
            "length": length,
            "loop_mode": loop_mode,
            "track_count": len(track_indices),
            "tracks_by_type": dict(tracks_by_type),
            "track_paths": track_paths,
            "sub_resource_id": sub_id,
            "source": "tscn_inline",
        })

    return results


# ---------------------------------------------------------------------------
# 2.2  _extract_animation_libraries
# ---------------------------------------------------------------------------

def _extract_animation_libraries(scene: TscnScene) -> dict[str, dict[str, str]]:
    """Extract AnimationLibrary sub_resources and their animation mappings.

    Handles both parsed dict format (single-line _data) and raw string
    format (multiline _data).

    Args:
        scene: A parsed TscnScene object.

    Returns:
        Dict keyed by library sub_resource id, values are dicts mapping
        animation name to Animation sub_resource id.
    """
    results: dict[str, dict[str, str]] = {}

    for sub_id, sub in scene.sub_resources.items():
        if sub.type != "AnimationLibrary":
            continue

        data = sub.properties.get("_data")
        if data is None:
            results[sub_id] = {}
            continue

        mapping: dict[str, str] = {}

        if isinstance(data, dict):
            # Format A: parsed Python dict
            for anim_name, ref in data.items():
                if isinstance(ref, dict) and ref.get("type") == "sub_resource":
                    mapping[str(anim_name)] = ref["id"]
        elif isinstance(data, str):
            # Format B: raw string
            for m in _RE_LIB_DATA.finditer(data):
                mapping[m.group(1)] = m.group(2)

        results[sub_id] = mapping

    return results


# ---------------------------------------------------------------------------
# 2.3  _extract_animation_players
# ---------------------------------------------------------------------------

def _extract_animation_players(scene: TscnScene) -> list[dict]:
    """Extract AnimationPlayer nodes and their library references.

    Args:
        scene: A parsed TscnScene object.

    Returns:
        List of player info dicts with name, path, and library_refs.
    """
    results: list[dict] = []

    for node in scene.get_nodes_by_type("AnimationPlayer"):
        path = node.name if node.parent == "." else f"{node.parent}/{node.name}"

        library_refs: dict[str, str] = {}
        libs_prop = node.properties.get("libraries")
        if isinstance(libs_prop, dict):
            for lib_name, ref in libs_prop.items():
                if isinstance(ref, dict) and ref.get("type") == "sub_resource":
                    library_refs[str(lib_name)] = ref["id"]

        results.append({
            "name": node.name,
            "path": path,
            "library_refs": library_refs,
        })

    return results


# ---------------------------------------------------------------------------
# 2.4  _extract_animation_trees
# ---------------------------------------------------------------------------

def _extract_animation_trees(scene: TscnScene) -> list[dict]:
    """Extract AnimationTree nodes with state machine data.

    Correlates AnimationTree nodes with AnimationNodeStateMachine and
    AnimationNodeAnimation sub_resources.

    Args:
        scene: A parsed TscnScene object.

    Returns:
        List of tree info dicts with node_name, node_path, anim_player_path,
        states, transitions, and animation_refs.
    """
    # Collect AnimationNodeAnimation refs
    anim_node_refs: dict[str, str] = {}  # sub_id -> animation name
    for sub_id, sub in scene.sub_resources.items():
        if sub.type == "AnimationNodeAnimation":
            anim_val = sub.properties.get("animation", "")
            anim_node_refs[sub_id] = str(_strip_string_name(anim_val))

    # Collect StateMachine data
    state_machines: dict[str, dict] = {}
    for sub_id, sub in scene.sub_resources.items():
        if sub.type != "AnimationNodeStateMachine":
            continue

        states: list[str] = []
        for key in sub.properties:
            m = _RE_STATE_NODE.match(key)
            if m:
                states.append(m.group(1))

        transitions: list[dict] = []
        trans_list = sub.properties.get("transitions")
        if isinstance(trans_list, list) and len(trans_list) >= 3:
            for i in range(0, len(trans_list) - 2, 3):
                from_state = str(_strip_string_name(trans_list[i]))
                to_state = str(_strip_string_name(trans_list[i + 1]))
                transitions.append({"from": from_state, "to": to_state})

        # Collect animation refs from states
        animation_refs: list[str] = []
        for state_name in states:
            node_key = f"states/{state_name}/node"
            node_ref = sub.properties.get(node_key)
            if isinstance(node_ref, dict) and node_ref.get("type") == "sub_resource":
                ref_id = node_ref["id"]
                if ref_id in anim_node_refs:
                    animation_refs.append(anim_node_refs[ref_id])

        state_machines[sub_id] = {
            "states": states,
            "transitions": transitions,
            "animation_refs": animation_refs,
        }

    # Build results from AnimationTree nodes
    results: list[dict] = []
    for node in scene.get_nodes_by_type("AnimationTree"):
        path = node.name if node.parent == "." else f"{node.parent}/{node.name}"
        anim_player_path = str(node.properties.get("anim_player", ""))

        tree_root = node.properties.get("tree_root")
        sm_data: dict = {"states": [], "transitions": [], "animation_refs": []}

        if isinstance(tree_root, dict) and tree_root.get("type") == "sub_resource":
            root_id = tree_root["id"]
            if root_id in state_machines:
                sm_data = state_machines[root_id]

        results.append({
            "node_name": node.name,
            "node_path": path,
            "anim_player_path": anim_player_path,
            "states": sm_data["states"],
            "transitions": sm_data["transitions"],
            "animation_refs": sm_data["animation_refs"],
        })

    return results


# ---------------------------------------------------------------------------
# 2.5  _extract_code_animations
# ---------------------------------------------------------------------------

def _extract_code_animations(gd_content: str) -> dict:
    """Extract animation-related patterns from GDScript source code.

    Scans for .play()/.queue()/.travel() calls, AnimationPlayer/Tree
    variable declarations, animation dicts (ANIM_MAP), and animation
    arrays (LOOPING_ANIMS).

    Args:
        gd_content: Raw GDScript source text.

    Returns:
        Dict with play_calls, travel_calls, anim_maps, looping_lists,
        has_anim_player, has_anim_tree, anim_player_vars, anim_tree_vars, source.
    """
    play_calls: list[str] = []
    travel_calls: list[str] = []
    anim_maps: list[dict] = []
    looping_lists: list[dict] = []
    anim_player_vars: list[str] = []
    anim_tree_vars: list[str] = []

    # Simple regex scans
    play_calls.extend(m.group(1) for m in _RE_PLAY.finditer(gd_content))
    play_calls.extend(m.group(1) for m in _RE_QUEUE.finditer(gd_content))
    travel_calls.extend(m.group(1) for m in _RE_TRAVEL.finditer(gd_content))
    anim_player_vars.extend(m.group(1) for m in _RE_ANIM_PLAYER_VAR.finditer(gd_content))
    anim_tree_vars.extend(m.group(1) for m in _RE_ANIM_TREE_VAR.finditer(gd_content))

    # Dict and array extraction with brace/bracket counting
    lines = gd_content.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]

        # Check for dict declarations
        dm = _RE_DICT_DECL.search(line)
        if dm and _is_anim_name(dm.group(1)):
            name = dm.group(1)
            body, end_i = _collect_balanced(lines, i, "{", "}")
            entries = dict(_RE_KV_PAIR.findall(body))
            anim_maps.append({"name": name, "entries": entries})
            i = end_i + 1
            continue

        # Check for array declarations
        am = _RE_ARRAY_DECL.search(line)
        if am and _is_anim_name(am.group(1)):
            name = am.group(1)
            body, end_i = _collect_balanced(lines, i, "[", "]")
            entries = _RE_QUOTED_STR.findall(body)
            looping_lists.append({"name": name, "entries": entries})
            i = end_i + 1
            continue

        i += 1

    return {
        "play_calls": play_calls,
        "travel_calls": travel_calls,
        "anim_maps": anim_maps,
        "looping_lists": looping_lists,
        "has_anim_player": len(anim_player_vars) > 0,
        "has_anim_tree": len(anim_tree_vars) > 0,
        "anim_player_vars": anim_player_vars,
        "anim_tree_vars": anim_tree_vars,
        "source": "code",
    }


def _is_anim_name(name: str) -> bool:
    """Check if a variable name looks animation-related."""
    lower = name.lower()
    return any(kw in lower for kw in _ANIM_NAME_KEYWORDS)


def _collect_balanced(
    lines: list[str], start: int, open_char: str, close_char: str
) -> tuple[str, int]:
    """Collect lines until brackets/braces are balanced.

    Args:
        lines: All source lines.
        start: Starting line index.
        open_char: Opening bracket character.
        close_char: Closing bracket character.

    Returns:
        Tuple of (collected text, end line index).
    """
    depth = 0
    collected: list[str] = []
    for i in range(start, len(lines)):
        line = lines[i]
        collected.append(line)
        depth += line.count(open_char) - line.count(close_char)
        if depth <= 0:
            return "\n".join(collected), i
    return "\n".join(collected), len(lines) - 1


# ---------------------------------------------------------------------------
# 2.6  _build_animation_summary
# ---------------------------------------------------------------------------

def _build_animation_summary(
    scene_path: str,
    scene: TscnScene,
    session: GodotIQSession,
) -> dict:
    """Aggregate all animation data for a single scene.

    Args:
        scene_path: The res:// path of the scene.
        scene: The parsed TscnScene object.
        session: A loaded GodotIQSession.

    Returns:
        Dict with animations, libraries, players, trees, code_animations,
        code_only, and unused lists.
    """
    animations = _extract_tscn_animations(scene)
    libraries = _extract_animation_libraries(scene)
    players = _extract_animation_players(scene)
    trees = _extract_animation_trees(scene)

    # Extract code animations from attached scripts
    code_animations: list[dict] = []
    script_paths = scene.get_all_scripts()
    for script_res in script_paths:
        try:
            fs_path = session._resolve_res_path(script_res)
            content = fs_path.read_text(encoding="utf-8")
            code_animations.append(_extract_code_animations(content))
        except (OSError, AttributeError):
            continue

    # Build known animation names from scene data
    scene_anim_names: set[str] = {a["name"] for a in animations}

    # Build referenced animation names from code + trees
    referenced_names: set[str] = set()
    for ca in code_animations:
        referenced_names.update(ca["play_calls"])
        referenced_names.update(ca["travel_calls"])
        for am in ca["anim_maps"]:
            referenced_names.update(am["entries"].values())
        for ll in ca["looping_lists"]:
            referenced_names.update(ll["entries"])
    for tree in trees:
        referenced_names.update(tree["animation_refs"])

    # Code-only: referenced but not in scene
    code_only = sorted(referenced_names - scene_anim_names)

    # Unused: in scene but not referenced (only if scripts exist or trees reference the player)
    has_references = bool(script_paths) or bool(trees)
    unused = sorted(scene_anim_names - referenced_names) if has_references else []

    return {
        "animations": animations,
        "libraries": libraries,
        "players": players,
        "trees": trees,
        "code_animations": code_animations,
        "code_only": code_only,
        "unused": unused,
    }


# ---------------------------------------------------------------------------
# 3.0  _build_animation_info
# ---------------------------------------------------------------------------

_MAX_ANIMATIONS_PER_PLAYER = 50


def _build_animation_info(
    session: GodotIQSession,
    scene_path: str,
    node: str | None = None,
    detail: str = "normal",
) -> dict:
    """Build animation info response for a scene.

    Args:
        session: A loaded GodotIQSession.
        scene_path: res:// path to the .tscn file.
        node: Optional AnimationPlayer node name to filter on.
        detail: "brief", "normal", or "full".

    Returns:
        Dict with animation_players, animation_trees, code_animations, summary.
    """
    scene = session.get_scene(scene_path)
    if scene is None:
        return {"error": "Scene not found", "scene": scene_path}

    summary = _build_animation_summary(scene_path, scene, session)
    detail = detail.lower()

    # Build player info with animations resolved through libraries
    libraries = summary["libraries"]
    anim_lookup: dict[str, dict] = {a["sub_resource_id"]: a for a in summary["animations"]}

    player_dicts: list[dict] = []
    for player in summary["players"]:
        # Resolve animations through libraries
        animations: list[dict] = []
        for _lib_name, lib_sub_id in player["library_refs"].items():
            lib_map = libraries.get(lib_sub_id, {})
            for anim_name, anim_sub_id in lib_map.items():
                anim_data = anim_lookup.get(anim_sub_id)
                if anim_data:
                    animations.append(anim_data)

        truncated = len(animations) > _MAX_ANIMATIONS_PER_PLAYER
        if truncated:
            animations = animations[:_MAX_ANIMATIONS_PER_PLAYER]

        # Apply detail level filtering to animations
        filtered_anims = _filter_animations_by_detail(animations, detail)

        player_dict: dict = {
            "name": player["name"],
            "path": player["path"],
            "animations": filtered_anims,
            "animation_count": len(filtered_anims),
        }
        if truncated:
            player_dict["truncated"] = True

        player_dicts.append(player_dict)

    # Node filtering
    if node is not None:
        matched = _match_player_by_node(player_dicts, node)
        if matched is None:
            available = [p["name"] for p in player_dicts]
            return {
                "error": f"No AnimationPlayer matching '{node}'",
                "alternatives": available,
                "scene": scene_path,
            }
        player_dicts = [matched]

    # Build tree dicts
    tree_dicts: list[dict] = []
    for tree in summary["trees"]:
        tree_dicts.append({
            "node_name": tree["node_name"],
            "node_path": tree["node_path"],
            "anim_player_path": tree["anim_player_path"],
            "states": tree["states"],
            "transitions": tree["transitions"],
            "animation_refs": tree["animation_refs"],
        })

    # Code animations (merged from all scripts)
    code_anim_dict: dict | None = None
    if summary["code_animations"]:
        merged = _merge_code_animations(summary["code_animations"])
        code_anim_dict = merged

    # Count unique animation names from the (possibly filtered) player list
    all_names: set[str] = set()
    inline_count = 0
    for player in player_dicts:
        for anim in player["animations"]:
            all_names.add(anim["name"])
            inline_count += 1

    # Only include code_only names when not filtering by node
    code_only_count = 0
    if node is None:
        for co in summary["code_only"]:
            all_names.add(co)
        code_only_count = len(summary["code_only"])

    # Always include code_animations key (empty dict when no scripts)
    code_anim_result: dict = code_anim_dict if code_anim_dict is not None else {}

    result: dict = {
        "scene": scene_path,
        "animation_players": player_dicts,
        "animation_trees": tree_dicts,
        "code_animations": code_anim_result,
        "summary": {
            "total_animations": len(all_names),
            "total_players": len(player_dicts),
            "total_trees": len(tree_dicts),
            "inline_count": inline_count,
            "code_only_count": code_only_count,
            "sources": _determine_sources(summary),
        },
    }

    return apply_output_limit(result, detail, list_keys=["animation_players"])


def _filter_animations_by_detail(animations: list[dict], detail: str) -> list[dict]:
    """Filter animation dicts based on detail level.

    brief: name only.
    normal: everything except track_paths.
    full: everything.
    """
    if detail == "brief":
        return [{"name": a["name"]} for a in animations]

    if detail == "full":
        return [dict(a) for a in animations]

    # normal — exclude track_paths
    result = []
    for a in animations:
        d = {k: v for k, v in a.items() if k != "track_paths"}
        result.append(d)
    return result


def _match_player_by_node(players: list[dict], node: str) -> dict | None:
    """Fuzzy-match a player by node name.

    Priority: exact name > case-insensitive > substring.
    """
    # Exact match
    for p in players:
        if p["name"] == node:
            return p
    # Case-insensitive
    lower = node.lower()
    for p in players:
        if p["name"].lower() == lower:
            return p
    # Substring
    for p in players:
        if lower in p["name"].lower():
            return p
    return None


def _merge_code_animations(code_anims: list[dict]) -> dict:
    """Merge multiple code animation results from different scripts."""
    merged: dict = {
        "play_calls": [],
        "travel_calls": [],
        "anim_maps": [],
        "looping_lists": [],
        "has_anim_player": False,
        "has_anim_tree": False,
        "anim_player_vars": [],
        "anim_tree_vars": [],
        "source": "code",
    }
    for ca in code_anims:
        merged["play_calls"].extend(ca.get("play_calls", []))
        merged["travel_calls"].extend(ca.get("travel_calls", []))
        merged["anim_maps"].extend(ca.get("anim_maps", []))
        merged["looping_lists"].extend(ca.get("looping_lists", []))
        merged["anim_player_vars"].extend(ca.get("anim_player_vars", []))
        merged["anim_tree_vars"].extend(ca.get("anim_tree_vars", []))
        if ca.get("has_anim_player"):
            merged["has_anim_player"] = True
        if ca.get("has_anim_tree"):
            merged["has_anim_tree"] = True
    return merged


def _determine_sources(summary: dict) -> list[str]:
    """Determine which animation sources are present."""
    sources: list[str] = []
    if summary["animations"]:
        sources.append("tscn_inline")
    # Only report "code" if scripts actually reference animations
    for ca in summary["code_animations"]:
        if ca.get("play_calls") or ca.get("travel_calls") or ca.get("anim_maps"):
            sources.append("code")
            break
    if summary["trees"]:
        sources.append("animation_tree")
    return sources


# ---------------------------------------------------------------------------
# MCP Tool: godotiq_animation_info
# ---------------------------------------------------------------------------

from godotiq.tools.output_limit import apply_output_limit
from godotiq.server import mcp  # noqa: E402
from godotiq.tool_runtime import guard_tool


@mcp.tool(
    name="godotiq_animation_info",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    },
)
@guard_tool("godotiq_animation_info")
async def godotiq_animation_info(
    scene: str,
    node: str | None = None,
    detail: str = "normal",
    ctx: Context = None,
) -> dict:
    """Animation data for any node: tracks, keyframes, length, looping, state machine transitions. Use to understand animation setup before modifying.

    Args:
        scene: Path to .tscn file (res:// or relative).
        node: AnimationPlayer name to filter on (shows all if omitted).
        detail: "brief" (animation names + lengths), "normal" (+ tracks, transitions), "full" (+ keyframe data).
    """
    session = ctx.request_context.lifespan_context["session"]
    if session is None:
        return {"error": "No Godot project loaded"}
    return _build_animation_info(session, scene, node, detail)


# ---------------------------------------------------------------------------
# 4.0  Animation Audit Stub
# ---------------------------------------------------------------------------


def _stub_animation_audit(
    session: GodotIQSession | None, scope: str,
    scene_filter: str | None, detail: str,
) -> dict:
    """Stub logic for godotiq_animation_audit."""
    if session is None:
        return {"error": "No Godot project loaded"}

    detail = detail.lower() if detail else "normal"

    impl = get_pro_implementation("godotiq_animation_audit")
    if impl is not None:
        return impl(session, scope, scene_filter, detail)

    if session.index is None:
        return {"error": "Project index not loaded."}

    teaser = {
        "total_animations": 0,
        "total_issues": 0,
        "by_severity": {},
    }
    return pro_unavailable_response("godotiq_animation_audit", teaser)


# ---------------------------------------------------------------------------
# MCP Tool: godotiq_animation_audit
# ---------------------------------------------------------------------------


@mcp.tool(
    name="godotiq_animation_audit",
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    },
)
@guard_tool("godotiq_animation_audit")
async def godotiq_animation_audit(
    scope: str = "all",
    scene: str | None = None,
    detail: str = "normal",
    ctx: Context = None,
) -> dict:
    """Find animation problems: broken tracks, missing transitions, wrong loop settings, unreferenced animations. Run before shipping to catch animation bugs.

    Args:
        scope: "all" (scan entire project) or "scene" (single scene).
        scene: Path to .tscn file when scope="scene".
        detail: "brief" (severity counts only), "normal" (+ issue list), "full".
    """
    session = ctx.request_context.lifespan_context["session"]
    return _stub_animation_audit(session, scope, scene, detail)
