"""Parser for GDScript .gd files.

Extracts signals, functions, class hierarchy, and dependency information
from GDScript source files.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from pathlib import Path

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Pre-compiled regex patterns
# ---------------------------------------------------------------------------

# --- Class-level declarations ---
_COMBINED_CLASS_EXTENDS_RE = re.compile(r"^class_name\s+(\w+)\s+extends\s+(.+)$")
_CLASS_NAME_RE = re.compile(r"^class_name\s+(\w+)")
_EXTENDS_RE = re.compile(r"^extends\s+(.+)$")

# --- Signals ---
_SIGNAL_RE = re.compile(r"^signal\s+(\w+)(?:\(([^)]*)\))?")

# --- Functions ---
_FUNC_START_RE = re.compile(r"^(?:static\s+)?func\s+(\w+)\s*\(")

# --- Variables ---
_VAR_RE = re.compile(
    r"^(var|const)\s+(\w+)\s*(?::\s*([^=:]+?))?\s*(?:(?::=|=)\s*(.+))?$"
)

# --- Enums ---
_ENUM_SINGLE_RE = re.compile(r"^enum\s+(\w+)?\s*\{([^}]*)\}")
_ENUM_START_RE = re.compile(r"^enum\s+(\w+)?\s*\{")

# --- Inner classes ---
_INNER_CLASS_RE = re.compile(r"^class\s+(\w+)\s*(?:extends\s+[\w.]+)?\s*:")

# --- Annotations ---
_ANNOTATION_VAR_RE = re.compile(r"^(@\w+(?:\([^)]*\))?)\s+(var|const)\s+")
_STANDALONE_ANNOTATION_RE = re.compile(r"^@(\w+)(?:\(([^)]*)\))?")

# --- Body patterns ---
_CONNECT_RE = re.compile(r"\.connect\(")
_EMIT_RE = re.compile(r"(\w+)\.emit\(")
_HAS_NODE_RE = re.compile(r'has_node\(\s*"(/root/[\w/]+)"\s*\)')
_GET_NODE_RE = re.compile(r'get_node\(\s*"(/root/[\w/]+)"\s*\)')
_GET_NODE_OR_NULL_RE = re.compile(r'get_node_or_null\(\s*"([^"]+)"\s*\)')
_IS_INSTANCE_VALID_RE = re.compile(r"is_instance_valid\(")
_PRELOAD_RE = re.compile(r'preload\(\s*"([^"]+)"\s*\)')
_LOAD_RE = re.compile(r'(?<!\w)load\(\s*"([^"]+)"\s*\)')

# ---------------------------------------------------------------------------
# Dataclasses
# ---------------------------------------------------------------------------


@dataclass
class GdSignal:
    """A signal declaration in a GDScript file."""

    name: str = ""
    args: list[tuple[str, str]] = field(default_factory=list)
    line: int = 0


@dataclass
class GdFunction:
    """A function declaration in a GDScript file."""

    name: str = ""
    args: list[tuple[str, str, str]] = field(default_factory=list)
    return_type: str = ""
    is_static: bool = False
    is_virtual: bool = False
    is_private: bool = False
    line: int = 0
    end_line: int = 0


@dataclass
class GdVariable:
    """A variable or constant declaration in a GDScript file."""

    name: str = ""
    type_hint: str = ""
    default_value: str = ""
    is_const: bool = False
    is_static: bool = False
    annotation: str = ""
    scope: str = "class"
    line: int = 0


@dataclass
class GdEnum:
    """An enum declaration in a GDScript file."""

    name: str = ""
    values: dict[str, int | None] = field(default_factory=dict)
    line: int = 0


@dataclass
class GdSignalConnection:
    """A signal .connect() call detected in a function body."""

    signal_source: str = ""
    target: str = ""
    has_bind: bool = False
    bind_args: str = ""
    line: int = 0


@dataclass
class GdSignalEmission:
    """A signal .emit() call detected in a function body."""

    signal_name: str = ""
    arg_count: int = 0
    line: int = 0


@dataclass
class GdAutoloadRef:
    """A reference to an autoload singleton detected in a function body."""

    autoload_name: str = ""
    access: str = ""
    pattern: str = ""
    line: int = 0


@dataclass
class GdPreloadRef:
    """A preload() or load() call detected in the file."""

    path: str = ""
    is_preload: bool = True
    line: int = 0


@dataclass
class GdScript:
    """Parsed representation of a .gd file."""

    class_name: str = ""
    extends: str = ""
    signals: list[GdSignal] = field(default_factory=list)
    functions: list[GdFunction] = field(default_factory=list)
    variables: list[GdVariable] = field(default_factory=list)
    enums: list[GdEnum] = field(default_factory=list)
    inner_classes: list[str] = field(default_factory=list)
    signal_connections: list[GdSignalConnection] = field(default_factory=list)
    signal_emissions: list[GdSignalEmission] = field(default_factory=list)
    autoload_refs: list[GdAutoloadRef] = field(default_factory=list)
    preload_refs: list[GdPreloadRef] = field(default_factory=list)
    is_instance_valid_lines: list[int] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------


def _strip_comment(line: str) -> str:
    """Strip inline comment from a line, respecting string literals.

    Scans left-to-right tracking quote state. Strips from first unquoted ``#``.
    Full-comment lines (leading whitespace + ``#``) are returned unchanged.
    """
    stripped = line.lstrip()
    if not stripped or stripped.startswith("#"):
        return line

    in_double = False
    in_single = False
    for i, ch in enumerate(line):
        if ch == '"' and not in_single:
            in_double = not in_double
        elif ch == "'" and not in_double:
            in_single = not in_single
        elif ch == "#" and not in_double and not in_single:
            return line[:i].rstrip()
    return line


def _split_args_depth_aware(args_str: str) -> list[str]:
    """Split an argument string by commas respecting nested brackets.

    Tracks depth for ``()``, ``[]``, and ``{}``.  Only splits on commas at
    depth zero.  Returns stripped strings; empty input returns an empty list.
    """
    args_str = args_str.strip()
    if not args_str:
        return []

    parts: list[str] = []
    current: list[str] = []
    paren = 0
    bracket = 0
    brace = 0

    for ch in args_str:
        if ch == "(":
            paren += 1
            current.append(ch)
        elif ch == ")":
            paren -= 1
            current.append(ch)
        elif ch == "[":
            bracket += 1
            current.append(ch)
        elif ch == "]":
            bracket -= 1
            current.append(ch)
        elif ch == "{":
            brace += 1
            current.append(ch)
        elif ch == "}":
            brace -= 1
            current.append(ch)
        elif ch == "," and paren == 0 and bracket == 0 and brace == 0:
            parts.append("".join(current).strip())
            current = []
        else:
            current.append(ch)

    tail = "".join(current).strip()
    if tail:
        parts.append(tail)
    return parts


def _find_matching_paren(line: str, start: int) -> int:
    """Return index of the closing ``)`` matching the ``(`` at *start*.

    Uses depth tracking.  Returns ``-1`` if no match is found.
    """
    depth = 0
    for i in range(start, len(line)):
        if line[i] == "(":
            depth += 1
        elif line[i] == ")":
            depth -= 1
            if depth == 0:
                return i
    return -1


def _parse_signal_args(args_str: str) -> list[tuple[str, str]]:
    """Parse a signal argument string into ``(name, type_hint)`` tuples.

    Untyped arguments get ``""`` as their type hint.
    """
    args_str = args_str.strip()
    if not args_str:
        return []

    result: list[tuple[str, str]] = []
    for part in args_str.split(","):
        part = part.strip()
        if not part:
            continue
        if ":" in part:
            name, type_hint = part.split(":", 1)
            result.append((name.strip(), type_hint.strip()))
        else:
            result.append((part, ""))
    return result


def _parse_func_args(args_str: str) -> list[tuple[str, str, str]]:
    """Parse function arguments into ``(name, type_hint, default)`` triples.

    Uses depth-aware splitting so defaults like ``Vector2(1, 2)`` are handled.
    """
    args_str = args_str.strip()
    if not args_str:
        return []

    result: list[tuple[str, str, str]] = []
    for part in _split_args_depth_aware(args_str):
        part = part.strip()
        if not part:
            continue

        name = part
        type_hint = ""
        default = ""

        if "=" in part:
            before_eq, default = part.split("=", 1)
            default = default.strip()
            before_eq = before_eq.strip().removesuffix(":")
            if ":" in before_eq:
                name, type_hint = before_eq.split(":", 1)
                name = name.strip()
                type_hint = type_hint.strip()
            else:
                name = before_eq.strip()
        elif ":" in part:
            name, type_hint = part.split(":", 1)
            name = name.strip()
            type_hint = type_hint.strip()

        result.append((name, type_hint, default))
    return result


def _count_emit_args(args_str: str) -> int:
    """Count arguments in an ``.emit()`` call using depth-aware comma counting.

    Returns 0 for empty/whitespace-only input, otherwise ``comma_count + 1``.
    """
    args_str = args_str.strip()
    if not args_str:
        return 0

    count = 0
    depth = 0
    for ch in args_str:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == "," and depth == 0:
            count += 1
    return count + 1


def _parse_enum_body(body: str) -> dict[str, int | None]:
    """Parse the body of an enum into ``{name: value}`` dict.

    Entries without explicit values get ``None``.  Supports negative integers.
    """
    body = body.strip()
    if not body:
        return {}

    result: dict[str, int | None] = {}
    for part in body.split(","):
        part = part.strip()
        if not part:
            continue
        if "=" in part:
            name, val = part.split("=", 1)
            try:
                result[name.strip()] = int(val.strip())
            except ValueError:
                result[name.strip()] = None
        else:
            result[part] = None
    return result


# ---------------------------------------------------------------------------
# State constants
# ---------------------------------------------------------------------------

_STATE_TOP_LEVEL = "TOP_LEVEL"
_STATE_IN_FUNCTION = "IN_FUNCTION"
_STATE_IN_ENUM = "IN_ENUM"
_STATE_IN_MULTILINE_VALUE = "IN_MULTILINE_VALUE"
_STATE_IN_INNER_CLASS = "IN_INNER_CLASS"

# Annotations that apply to variables (bufferable)
_VAR_ANNOTATIONS = frozenset({"export", "export_range", "export_enum",
                               "export_file", "export_dir", "export_multiline",
                               "export_placeholder", "export_color_no_alpha",
                               "export_node_path", "export_flags",
                               "export_flags_2d_physics", "export_flags_2d_render",
                               "export_flags_2d_navigation",
                               "export_flags_3d_physics", "export_flags_3d_render",
                               "export_flags_3d_navigation",
                               "onready"})

# Grouping annotations to discard (not buffered)
_GROUP_ANNOTATIONS = frozenset({"export_group", "export_subgroup",
                                 "export_category"})


def _get_indent(line: str) -> int:
    """Return count of leading whitespace characters."""
    return len(line) - len(line.lstrip())


def _bracket_depth(text: str) -> int:
    """Count net bracket depth in *text* (``[{`` +1, ``]}`` -1)."""
    depth = 0
    for ch in text:
        if ch in "[{":
            depth += 1
        elif ch in "]}":
            depth -= 1
    return depth


_PROPERTY_RE = re.compile(r"^(var|const)\s+(\w+)\s*:\s*([\w.\[\], ]+?)\s*:\s*$")


def _parse_var_line(var_line: str, lineno: int, *,
                    is_static: bool = False,
                    annotation: str = "") -> tuple[GdVariable | None, str | None]:
    """Parse a var/const line and return (variable, state_to_enter).

    Returns ``(None, None)`` if the line doesn't match.
    *state_to_enter* is ``"IN_MULTILINE_VALUE"`` or ``"IN_FUNCTION"``
    (for property getter/setter) or ``None`` for a normal single-line var.
    """
    # Property getter/setter: "var health: int:" — trailing colon, no default
    pm = _PROPERTY_RE.match(var_line)
    if pm:
        var = GdVariable(
            name=pm.group(2),
            type_hint=pm.group(3),
            is_const=(pm.group(1) == "const"),
            is_static=is_static,
            annotation=annotation,
            scope="class",
            line=lineno,
        )
        return var, _STATE_IN_FUNCTION

    m = _VAR_RE.match(var_line)
    if not m:
        return None, None

    keyword, name, type_hint, default = m.groups()
    type_hint = (type_hint or "").strip()
    default = (default or "").strip()

    var = GdVariable(
        name=name,
        type_hint=type_hint,
        default_value=default,
        is_const=(keyword == "const"),
        is_static=is_static,
        annotation=annotation,
        scope="class",
        line=lineno,
    )

    # Multiline value: unclosed brackets
    if default and _bracket_depth(default) > 0:
        return var, _STATE_IN_MULTILINE_VALUE

    return var, None


# ---------------------------------------------------------------------------
# Core parser
# ---------------------------------------------------------------------------


def _parse_gd_content(
    content: str, known_autoloads: list[str] | None = None
) -> GdScript:
    """Parse GDScript content string into a GdScript dataclass.

    This is the internal parsing function.  Use ``parse_gd()`` for
    file-based parsing.

    Args:
        content: Raw GDScript source text.
        known_autoloads: Optional list of known autoload names for detection.

    Returns:
        Populated ``GdScript`` dataclass.  Never raises on malformed content.
    """
    result = GdScript()

    # Compile autoload direct-pattern regex once per parse invocation
    re_autoload_direct = None
    if known_autoloads:
        alt = "|".join(re.escape(name) for name in known_autoloads)
        re_autoload_direct = re.compile(rf"\b({alt})\.(\w+)")

    state = _STATE_TOP_LEVEL

    # Function tracking
    current_func: GdFunction | None = None
    func_indent = 0
    last_nonblank_line = 0

    # Enum accumulation
    enum_buffer: list[str] = []
    enum_name = ""
    enum_line = 0
    enum_depth = 0

    # Multiline value accumulation
    multiline_var: GdVariable | None = None
    multiline_depth = 0

    # Inner class tracking
    inner_class_indent = 0

    # Annotation buffer
    annotation_buffer = ""

    lines = content.split("\n") if content else []

    i = 0
    while i < len(lines):
        lineno = i + 1  # 1-indexed
        raw_line = lines[i]
        i += 1

        # -- All-state scanning: preload/load and is_instance_valid --
        for plm in _PRELOAD_RE.finditer(raw_line):
            result.preload_refs.append(
                GdPreloadRef(path=plm.group(1), is_preload=True, line=lineno)
            )
        for lm in _LOAD_RE.finditer(raw_line):
            result.preload_refs.append(
                GdPreloadRef(path=lm.group(1), is_preload=False, line=lineno)
            )
        if _IS_INSTANCE_VALID_RE.search(raw_line):
            result.is_instance_valid_lines.append(lineno)

        stripped = raw_line.strip()

        # ---------------------------------------------------------------
        # IN_ENUM state
        # ---------------------------------------------------------------
        if state == _STATE_IN_ENUM:
            enum_buffer.append(stripped)
            enum_depth += stripped.count("{") - stripped.count("}")
            if enum_depth <= 0:
                body = " ".join(enum_buffer)
                # Remove everything up to first { and after last }
                start = body.find("{")
                end = body.rfind("}")
                if start != -1 and end != -1:
                    body = body[start + 1:end]
                result.enums.append(
                    GdEnum(name=enum_name, values=_parse_enum_body(body),
                           line=enum_line)
                )
                state = _STATE_TOP_LEVEL
            continue

        # ---------------------------------------------------------------
        # IN_MULTILINE_VALUE state
        # ---------------------------------------------------------------
        if state == _STATE_IN_MULTILINE_VALUE:
            multiline_depth += _bracket_depth(stripped)
            if multiline_var is not None:
                multiline_var.default_value += "\n" + stripped
            if multiline_depth <= 0:
                if multiline_var is not None:
                    result.variables.append(multiline_var)
                    multiline_var = None
                state = _STATE_TOP_LEVEL
            continue

        # ---------------------------------------------------------------
        # IN_INNER_CLASS state
        # ---------------------------------------------------------------
        if state == _STATE_IN_INNER_CLASS:
            if not stripped:
                continue
            if _get_indent(raw_line) <= inner_class_indent:
                state = _STATE_TOP_LEVEL
                i -= 1  # re-process this line in TOP_LEVEL
            continue

        # ---------------------------------------------------------------
        # IN_FUNCTION state
        # ---------------------------------------------------------------
        if state == _STATE_IN_FUNCTION:
            if not stripped or stripped.startswith("#"):
                continue
            indent = _get_indent(raw_line)
            if indent <= func_indent:
                # Exited function — set end_line and re-process
                if current_func is not None:
                    current_func.end_line = last_nonblank_line
                    current_func = None
                state = _STATE_TOP_LEVEL
                i -= 1  # re-process current line
                continue
            # Body line — track last non-blank for end_line
            last_nonblank_line = lineno

            # --- Body pattern scanning (section 03) ---
            cleaned_body = _strip_comment(stripped)

            # .connect() detection (depth-aware)
            cm = _CONNECT_RE.search(cleaned_body)
            if cm:
                before_connect = cleaned_body[:cm.start()]
                source_m = re.search(r"([\w.$]+)$", before_connect.rstrip())
                signal_source = source_m.group(1) if source_m else before_connect.strip()
                paren_pos = cm.end() - 1  # position of opening (
                close_paren = _find_matching_paren(cleaned_body, paren_pos)
                if close_paren != -1:
                    args_content = cleaned_body[paren_pos + 1:close_paren]
                    has_bind = ".bind(" in args_content
                    bind_args = ""
                    target = args_content.strip()
                    if has_bind:
                        bind_idx = args_content.index(".bind(")
                        target = args_content[:bind_idx].strip()
                        bind_start = args_content.index("(", bind_idx)
                        bind_close = _find_matching_paren(args_content, bind_start)
                        if bind_close != -1:
                            bind_args = args_content[bind_start + 1:bind_close].strip()
                    result.signal_connections.append(
                        GdSignalConnection(
                            signal_source=signal_source,
                            target=target,
                            has_bind=has_bind,
                            bind_args=bind_args,
                            line=lineno,
                        )
                    )

            # .emit() detection with arg counting
            em = _EMIT_RE.search(cleaned_body)
            if em:
                signal_name = em.group(1)
                paren_pos = em.end() - 1
                close_paren = _find_matching_paren(cleaned_body, paren_pos)
                if close_paren != -1:
                    args_str = cleaned_body[paren_pos + 1:close_paren]
                    result.signal_emissions.append(
                        GdSignalEmission(
                            signal_name=signal_name,
                            arg_count=_count_emit_args(args_str),
                            line=lineno,
                        )
                    )

            # Autoload direct pattern (finditer for multiple matches per line)
            if re_autoload_direct is not None:
                for am in re_autoload_direct.finditer(cleaned_body):
                    result.autoload_refs.append(
                        GdAutoloadRef(
                            autoload_name=am.group(1),
                            access=am.group(2),
                            pattern="direct",
                            line=lineno,
                        )
                    )

            # has_node pattern
            hm = _HAS_NODE_RE.search(cleaned_body)
            if hm:
                path = hm.group(1)
                result.autoload_refs.append(
                    GdAutoloadRef(
                        autoload_name=path.split("/")[-1],
                        access="",
                        pattern="has_node",
                        line=lineno,
                    )
                )

            # get_node pattern (won't match get_node_or_null due to _or_null before paren)
            gm = _GET_NODE_RE.search(cleaned_body)
            if gm:
                path = gm.group(1)
                result.autoload_refs.append(
                    GdAutoloadRef(
                        autoload_name=path.split("/")[-1],
                        access="",
                        pattern="get_node",
                        line=lineno,
                    )
                )

            # get_node_or_null pattern
            gnm = _GET_NODE_OR_NULL_RE.search(cleaned_body)
            if gnm:
                full_path = gnm.group(1)
                name = full_path.split("/")[-1]
                result.autoload_refs.append(
                    GdAutoloadRef(
                        autoload_name=name,
                        access=full_path,
                        pattern="get_node_or_null",
                        line=lineno,
                    )
                )

            continue

        # ---------------------------------------------------------------
        # TOP_LEVEL state
        # ---------------------------------------------------------------
        if not stripped or stripped.startswith("#"):
            continue

        # Strip inline comment before matching
        cleaned = _strip_comment(stripped)

        # 1. Combined class_name + extends
        m = _COMBINED_CLASS_EXTENDS_RE.match(cleaned)
        if m:
            result.class_name = m.group(1)
            result.extends = m.group(2).strip()
            annotation_buffer = ""
            continue

        # 2. class_name
        m = _CLASS_NAME_RE.match(cleaned)
        if m:
            result.class_name = m.group(1)
            annotation_buffer = ""
            continue

        # 3. extends
        m = _EXTENDS_RE.match(cleaned)
        if m:
            result.extends = m.group(1).strip()
            annotation_buffer = ""
            continue

        # 4. signal
        m = _SIGNAL_RE.match(cleaned)
        if m:
            sig_name = m.group(1)
            sig_args_str = m.group(2) or ""
            result.signals.append(
                GdSignal(
                    name=sig_name,
                    args=_parse_signal_args(sig_args_str),
                    line=lineno,
                )
            )
            annotation_buffer = ""
            continue

        # 5. Enum (single-line first, then multiline start)
        m = _ENUM_SINGLE_RE.match(cleaned)
        if m:
            result.enums.append(
                GdEnum(
                    name=m.group(1) or "",
                    values=_parse_enum_body(m.group(2)),
                    line=lineno,
                )
            )
            annotation_buffer = ""
            continue
        m = _ENUM_START_RE.match(cleaned)
        if m:
            enum_name = m.group(1) or ""
            enum_line = lineno
            enum_buffer = [cleaned]
            enum_depth = cleaned.count("{") - cleaned.count("}")
            state = _STATE_IN_ENUM
            annotation_buffer = ""
            continue

        # 6. Annotation + var on same line
        m = _ANNOTATION_VAR_RE.match(cleaned)
        if m:
            ann = m.group(1)
            rest = cleaned[m.end():].strip()
            # re-parse "var ..." portion
            var_line_text = m.group(2) + " " + rest
            var, next_state = _parse_var_line(var_line_text, lineno,
                                              annotation=ann)
            if var is not None:
                if next_state == _STATE_IN_MULTILINE_VALUE:
                    multiline_var = var
                    multiline_depth = _bracket_depth(var.default_value)
                    state = _STATE_IN_MULTILINE_VALUE
                elif next_state == _STATE_IN_FUNCTION:
                    result.variables.append(var)
                    func_indent = 0
                    current_func = None
                    last_nonblank_line = lineno
                    state = _STATE_IN_FUNCTION
                else:
                    result.variables.append(var)
            annotation_buffer = ""
            continue

        # 7. Standalone annotation
        m = _STANDALONE_ANNOTATION_RE.match(cleaned)
        if m:
            ann_name = m.group(1)
            if ann_name in _GROUP_ANNOTATIONS:
                # Discard grouping annotations
                continue
            if ann_name.startswith("export") or ann_name in _VAR_ANNOTATIONS:
                # Buffer for next var
                annotation_buffer = cleaned  # full "@export_range(0, 100)"
                continue
            # Non-var annotations (@rpc, @warning_ignore, etc.) — discard
            continue

        # 8. Inner class
        m = _INNER_CLASS_RE.match(cleaned)
        if m:
            result.inner_classes.append(m.group(1))
            inner_class_indent = _get_indent(raw_line)
            state = _STATE_IN_INNER_CLASS
            annotation_buffer = ""
            continue

        # 9. Function (static or regular)
        m = _FUNC_START_RE.match(cleaned)
        if m:
            func_name = m.group(1)
            is_static = cleaned.startswith("static ")

            # Extract full arg string using depth-aware paren matching
            paren_start = cleaned.index("(")
            paren_end = _find_matching_paren(cleaned, paren_start)
            if paren_end == -1:
                paren_end = len(cleaned) - 1

            args_str = cleaned[paren_start + 1:paren_end]
            func_args = _parse_func_args(args_str)

            # Extract return type
            return_type = ""
            after_paren = cleaned[paren_end + 1:].strip()
            if after_paren.startswith("->"):
                rt = after_paren[2:].strip()
                # Remove trailing colon
                if rt.endswith(":"):
                    rt = rt[:-1].strip()
                return_type = rt

            func = GdFunction(
                name=func_name,
                args=func_args,
                return_type=return_type,
                is_static=is_static,
                is_virtual=func_name.startswith("_"),
                is_private=func_name.startswith("_"),
                line=lineno,
                end_line=lineno,
            )
            result.functions.append(func)

            # Check for one-liner: content after the colon
            colon_idx = cleaned.rfind(":")
            if colon_idx != -1:
                after_colon = cleaned[colon_idx + 1:].strip()
                if after_colon:
                    # One-liner function — end_line == line, stay TOP_LEVEL
                    func.end_line = lineno
                    annotation_buffer = ""
                    continue

            current_func = func
            func_indent = _get_indent(raw_line)
            last_nonblank_line = lineno
            state = _STATE_IN_FUNCTION
            annotation_buffer = ""
            continue

        # 10. Static var
        if cleaned.startswith("static "):
            rest = cleaned[7:]  # len("static ") == 7
            if rest.startswith("var ") or rest.startswith("const "):
                var, next_state = _parse_var_line(
                    rest, lineno, is_static=True,
                    annotation=annotation_buffer,
                )
                annotation_buffer = ""
                if var is not None:
                    if next_state == _STATE_IN_MULTILINE_VALUE:
                        multiline_var = var
                        multiline_depth = _bracket_depth(var.default_value)
                        state = _STATE_IN_MULTILINE_VALUE
                    elif next_state == _STATE_IN_FUNCTION:
                        result.variables.append(var)
                        func_indent = 0
                        current_func = None
                        last_nonblank_line = lineno
                        state = _STATE_IN_FUNCTION
                    else:
                        result.variables.append(var)
                continue

        # 11. var / const
        if cleaned.startswith("var ") or cleaned.startswith("const "):
            var, next_state = _parse_var_line(
                cleaned, lineno,
                annotation=annotation_buffer,
            )
            annotation_buffer = ""
            if var is not None:
                if next_state == _STATE_IN_MULTILINE_VALUE:
                    multiline_var = var
                    multiline_depth = _bracket_depth(var.default_value)
                    state = _STATE_IN_MULTILINE_VALUE
                elif next_state == _STATE_IN_FUNCTION:
                    result.variables.append(var)
                    func_indent = 0
                    current_func = None
                    last_nonblank_line = lineno
                    state = _STATE_IN_FUNCTION
                else:
                    result.variables.append(var)
            continue

    # -- End-of-file cleanup --
    if state == _STATE_IN_FUNCTION and current_func is not None:
        current_func.end_line = last_nonblank_line
    if state == _STATE_IN_MULTILINE_VALUE and multiline_var is not None:
        result.variables.append(multiline_var)
    if state == _STATE_IN_ENUM:
        body = " ".join(enum_buffer)
        start = body.find("{")
        end = body.rfind("}")
        if start != -1 and end != -1:
            body = body[start + 1:end]
        elif start != -1:
            body = body[start + 1:]
        result.enums.append(
            GdEnum(name=enum_name, values=_parse_enum_body(body),
                   line=enum_line)
        )

    return result


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def parse_gd(path: str, known_autoloads: list[str] | None = None) -> GdScript:
    """Parse a .gd file into a structured GdScript representation.

    Args:
        path: Absolute or relative path to a .gd file.
        known_autoloads: Optional list of known autoload singleton names
                         for accurate autoload reference detection.

    Returns:
        Parsed GdScript dataclass with all extracted structural information.
        Never raises on malformed content — uses best-effort parsing.

    Raises:
        FileNotFoundError: If the file does not exist.
    """
    content = Path(path).read_text(encoding="utf-8")
    return _parse_gd_content(content, known_autoloads)
