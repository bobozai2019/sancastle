"""GodotIQ MCP server — entry point and tool registration."""

from __future__ import annotations

import logging
import re
import sys
from contextlib import asynccontextmanager
from pathlib import Path

from mcp.server.fastmcp import FastMCP

from godotiq import __version__
from godotiq.config import load_config
from godotiq.session import GodotIQSession, discover_project_root

# --- Startup logging to stderr so diagnostics are visible in MCP hosts ---
_startup_handler = logging.StreamHandler(sys.stderr)
_startup_handler.setFormatter(
    logging.Formatter("[godotiq] %(levelname)s: %(message)s")
)
logging.getLogger("godotiq").addHandler(_startup_handler)
logging.getLogger("godotiq").setLevel(logging.INFO)

logger = logging.getLogger(__name__)


@asynccontextmanager
async def godotiq_lifespan(server):
    """Initialize GodotIQ session on server startup."""
    project_root = discover_project_root()
    from godotiq.bridge.session import configure_bridge

    if project_root is not None:
        logger.info("Project root: %s", project_root)
        session = GodotIQSession(project_root)
        try:
            session.load()
        except Exception:
            logger.exception("Failed to load project at %s", project_root)
            session = None
        else:
            logger.info(
                "Session loaded: %s (%d scripts, %d scenes)",
                session._index.project_name,
                session._index.total_scripts,
                session._index.total_scenes,
            )
            try:
                _check_rules_freshness(project_root)
            except Exception:
                pass  # never block startup
            configure_bridge(project_root, session.config)
    else:
        session = None
        logger.warning("No Godot project found. Tools will return errors.")
        configure_bridge(None, None)

    # Pro bundle warmup — never blocks startup or event loop
    try:
        import asyncio
        from godotiq.pro_loader import ensure_pro_bundle
        await asyncio.to_thread(ensure_pro_bundle)
    except Exception:
        logger.warning("Pro bundle loading failed; continuing in community mode", exc_info=True)

    try:
        yield {"session": session}
    finally:
        from godotiq.bridge.session import close_bridge
        await close_bridge()


mcp = FastMCP(name="godotiq", lifespan=godotiq_lifespan)

# Fix __main__ double-import: when run via `python -m godotiq.server`,
# this module is loaded as __main__. Tool modules that do
# `from godotiq.server import mcp` would trigger a second import,
# creating a separate mcp instance. Register ourselves under the
# canonical name so all imports share the same mcp object.
sys.modules.setdefault("godotiq.server", sys.modules[__name__])


_original_list_tools = mcp._tool_manager.list_tools


def _list_tools_filtered():
    """Hide tools disabled by the active project config from the catalog."""
    project_root = discover_project_root()
    if project_root is None:
        return _original_list_tools()

    config = load_config(str(project_root / ".godotiq.json"))
    disabled = {
        tool_name for tool_name in config.disabled_tools if tool_name != "godotiq_ping"
    }
    if not disabled:
        return _original_list_tools()

    return [tool for tool in _original_list_tools() if tool.name not in disabled]


mcp._tool_manager.list_tools = _list_tools_filtered


PROMPT_DIR = Path(__file__).resolve().parent / "prompts"

_RULES_VERSION_RE = re.compile(r"<!--\s*godotiq-rules-version:\s*(\S+)\s*-->")


def _extract_rules_version(text: str) -> str | None:
    """Extract the godotiq-rules-version from a markdown comment, or None."""
    m = _RULES_VERSION_RE.search(text)
    return m.group(1) if m else None


def _check_rules_freshness(project_root: Path) -> None:
    """Log a warning if the project's GODOTIQ_RULES.md is outdated or missing."""
    rules_path = project_root / "GODOTIQ_RULES.md"
    if not rules_path.exists():
        logger.info(
            "No GODOTIQ_RULES.md found. "
            "Run: godotiq install-addon %s",
            project_root,
        )
        return

    bundled_path = PROMPT_DIR / "godot_development.md"
    try:
        bundled_text = bundled_path.read_text(encoding="utf-8")
    except Exception:
        return  # can't read bundled file — skip check silently
    bundled_version = _extract_rules_version(bundled_text)
    if bundled_version is None:
        return  # bundled file has no version marker — skip check

    try:
        project_text = rules_path.read_text(encoding="utf-8")
    except Exception:
        logger.info(
            "Could not read GODOTIQ_RULES.md. "
            "Run: godotiq install-addon %s",
            project_root,
        )
        return

    project_version = _extract_rules_version(project_text)
    if project_version is None:
        logger.info(
            "GODOTIQ_RULES.md is outdated (project: unknown, current: %s). "
            "Run: godotiq install-addon %s",
            bundled_version,
            project_root,
        )
        return

    if project_version != bundled_version:
        logger.info(
            "GODOTIQ_RULES.md is outdated (project: %s, current: %s). "
            "Run: godotiq install-addon %s",
            project_version,
            bundled_version,
            project_root,
        )


@mcp.prompt("godot-development")
async def godot_development_prompt() -> str:
    """GodotIQ development guide — tool workflows, conventions, best practices."""
    return (PROMPT_DIR / "godot_development.md").read_text(encoding="utf-8")


_cached_update_version: str | None = None
_update_checked: bool = False


_PEP440_PRE_SUFFIX_RE = re.compile(
    r"(?i)(a|alpha|b|beta|c|rc|dev|pre|preview|post)\d*$"
)


def _version_triple(v: str) -> list[int]:
    """Parse a PEP 440 version string into a numeric list for comparison.

    Pre-release / dev / post suffixes are stripped so a prerelease
    collapses to its base triple. Malformed segments become 0.
    """
    clean = v.split("-")[0].split("+")[0]
    out: list[int] = []
    for part in clean.split("."):
        stripped = _PEP440_PRE_SUFFIX_RE.sub("", part) or "0"
        try:
            out.append(int(stripped))
        except ValueError:
            out.append(0)
    return out


def _is_newer_version(remote: str, local: str) -> bool:
    """Return True if remote version is strictly newer than local.

    Pre-release versions collapse to their base triple — we never want
    the editor panel to nag stable users that a ``0.5.1rc0`` is "newer"
    than ``0.5.0``. A prerelease routed to PyPI by mistake simply does
    not trigger the popup.
    """
    r = _version_triple(remote)
    l = _version_triple(local)  # noqa: E741
    max_len = max(len(r), len(l))
    for i in range(max_len):
        rv = r[i] if i < len(r) else 0
        lv = l[i] if i < len(l) else 0
        if rv > lv:
            return True
        if rv < lv:
            return False
    return False


async def _check_pypi_update() -> str | None:
    """Check PyPI for a newer version. Returns version string or None."""
    global _cached_update_version, _update_checked
    if _update_checked:
        return _cached_update_version
    _update_checked = True
    try:
        import httpx

        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get("https://pypi.org/pypi/godotiq/json")
            if resp.status_code == 200:
                remote = resp.json()["info"]["version"]
                if _is_newer_version(remote, __version__):
                    _cached_update_version = remote
    except Exception:
        pass
    return _cached_update_version


_TOOL_COUNT_FALLBACK = 38  # 24 Community + 14 Pro (see CLAUDE.md)


def _count_registered_tools() -> int:
    """Return the number of tools currently registered on the mcp instance.

    Best-effort: reads FastMCP's private ``_tool_manager._tools`` accessor
    (stable across FastMCP 1.x as currently observed). Falls back to
    ``_TOOL_COUNT_FALLBACK`` with a ``warning``-level log if that surface
    changes so operators notice the silent contract regression in logs.
    """
    try:
        tools = mcp._tool_manager._tools  # type: ignore[attr-defined]
        if isinstance(tools, dict):
            return len(tools)
        return int(len(tools))
    except Exception:  # noqa: BLE001 - defensive: never crash ping
        logger.warning(
            "mcp._tool_manager._tools unavailable; using fallback tool_count=%d",
            _TOOL_COUNT_FALLBACK,
            exc_info=True,
        )
        return _TOOL_COUNT_FALLBACK


@mcp.tool()
async def godotiq_ping(detail: str = "normal") -> dict:
    """Health check tool. Returns server status, version, license tier,
    receipt status, bundle status, tool count, and any available update.

    The returned dict is a public contract (consumed by the release
    checklist and the mirror README template). Keys are stable for 0.5.0.

    Args:
        detail: Output verbosity — "brief" (summary), "normal" (default),
            or "full" (everything). Currently does not gate output shape;
            reserved for future use.
    """
    from godotiq.license import license_diagnostic

    # license_diagnostic() calls is_pro() exactly once and returns a snapshot
    # consistent with what Pro tool stubs use for their gating decision —
    # eliminates skew between ping output and actual tool behavior.
    diag = license_diagnostic()

    result = {
        "status": "ok",
        "version": __version__,
        "license": diag["tier"],
        "receipt": diag["receipt"],
        "bundle": diag["bundle"],
        "pro_bundle": diag["bundle"],  # back-compat alias; deprecate in a future release
        "license_key_configured": diag["license_key_configured"],
        "tool_count": _count_registered_tools(),
    }

    if not diag["ok"]:
        # Surface the exact reason + actionable hint Pro tools will report
        # when called. Keys: license_state, license_error, manage, upgrade.
        result["license_state"] = diag.get("reason", diag["receipt"])
        result["license_error"] = diag.get("hint", "")
        result["manage"] = diag.get("manage", "")
        result["upgrade"] = diag.get("upgrade", "")
        if diag["tier"] == "pro":
            # Receipt is good but bundle didn't load; keep the legacy warning
            # phrasing so external scrapers (release checklist, mirror README)
            # still match. The license_error field above carries the new hint.
            result["warning"] = (
                f"Pro license detected but bundle is {diag['bundle']}. "
                "Pro tools will return licensing errors."
            )

    update = await _check_pypi_update()
    if update:
        result["update_available"] = update
    return result


# Tool imports — each module registers tools on the mcp instance
from godotiq.tools import memory  # noqa: E402, F401
from godotiq.tools import code  # noqa: E402, F401
from godotiq.tools import spatial  # noqa: E402, F401
from godotiq.tools import assets  # noqa: E402, F401
from godotiq.tools import animation  # noqa: E402, F401
from godotiq.tools import bridge  # noqa: E402, F401
from godotiq.tools import flow  # noqa: E402, F401


def main() -> None:
    """Start the GodotIQ MCP server with stdio transport."""
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
