"""Project run verification orchestration for the Godot bridge."""

from __future__ import annotations

import asyncio
from pathlib import Path
from typing import Any

from godotiq.bridge.connection import BridgeConnectionError, BridgeError, BridgeTimeoutError
from godotiq.tools.bridge.check_errors import check_errors
from godotiq.tools.bridge.debug_console import read_debug_console
from godotiq.tools.bridge.run import run


_FAIL_SEVERITIES = {"error", "script_error", "shader_error", "fatal"}


async def verify_project_runs(
    scene: str = "main",
    check_scope: str = "scene",
    startup_timeout: float = 0,
    settle_seconds: float = 1.0,
    error_limit: int = 20,
    stop_after: bool = True,
    fail_on_warnings: bool = False,
    project_root: str | Path | None = None,
) -> dict:
    """Launch the project and return a conservative PASS/FAIL/INCONCLUSIVE verdict.

    PASS is returned only when script preflight succeeds, the scene starts, and
    the debug console can be read after a short settle window with no failing
    entries. Any unavailable observation channel is INCONCLUSIVE, not PASS.
    """
    settle_seconds = max(0.0, min(float(settle_seconds), 10.0))
    error_limit = max(1, min(int(error_limit), 100))
    checks: dict[str, Any] = {}
    notes: list[str] = []

    script_check = await _safe_check_errors(check_scope)
    checks["script_check"] = script_check
    if script_check["status"] != "ok":
        return _verdict(
            "INCONCLUSIVE",
            "script_check",
            scene,
            checks,
            notes,
            f"Could not run script preflight: {script_check.get('error', 'unknown error')}",
        )
    script_errors = script_check["result"].get("errors", [])
    if script_errors:
        return _verdict(
            "FAIL",
            "script_check",
            scene,
            checks,
            notes,
            f"Script preflight found {len(script_errors)} error(s).",
            errors=script_errors,
            next_action="Fix godotiq_check_errors results before pressing Play.",
        )

    pre_clear = await _safe_read_debug_console(error_limit, clear=True)
    checks["pre_clear_debug_console"] = pre_clear
    if pre_clear["status"] != "ok":
        notes.append("Could not clear stale debug console entries before launch.")

    launch = await _safe_run(scene, startup_timeout, project_root)
    checks["launch"] = launch
    if launch["status"] != "ok":
        verdict = "FAIL" if launch.get("code") in {"SCRIPT_ERRORS", "RUN_TIMEOUT"} else "INCONCLUSIVE"
        return _verdict(
            verdict,
            "launch",
            scene,
            checks,
            notes,
            f"Scene launch did not complete: {launch.get('error', 'unknown error')}",
            next_action="Read launch error, then fix before declaring the game runnable.",
        )
    launch_result = launch.get("result", {})
    if launch_result.get("success") is False:
        return _verdict(
            "FAIL",
            "launch",
            scene,
            checks,
            notes,
            str(launch_result.get("error", "Scene launch returned success=false.")),
            errors=[launch_result],
            next_action="Fix the launch failure, then rerun godotiq_verify_project_runs.",
        )

    if settle_seconds > 0:
        await asyncio.sleep(settle_seconds)

    debug_console = await _safe_read_debug_console(error_limit, clear=False)
    checks["debug_console"] = debug_console
    if debug_console["status"] != "ok":
        verdict = _verdict(
            "INCONCLUSIVE",
            "debug_console",
            scene,
            checks,
            notes,
            f"Scene started, but debug console could not be read: {debug_console.get('error', 'unknown error')}",
            next_action="Do not report PASS until debug console is readable.",
        )
    else:
        entries = debug_console["result"].get("entries", [])
        failures = _failing_entries(entries, fail_on_warnings=fail_on_warnings)
        warnings = _warning_entries(entries)
        if failures:
            verdict = _verdict(
                "FAIL",
                "runtime",
                scene,
                checks,
                notes,
                f"Scene started but debug console reported {len(failures)} failing entry/entries.",
                errors=failures,
                next_action="Fix the debug console errors, then rerun godotiq_verify_project_runs.",
            )
        else:
            verdict = _verdict(
                "PASS",
                "complete",
                scene,
                checks,
                notes,
                "Scene started and no failing debug console entries were captured.",
            )
            if warnings:
                verdict["warnings"] = warnings

    if stop_after:
        checks["stop"] = await _safe_stop()
        verdict["checks"] = checks
    return verdict


async def _safe_check_errors(scope: str) -> dict:
    try:
        return {"status": "ok", "result": await check_errors(scope=scope)}
    except (BridgeConnectionError, BridgeTimeoutError, BridgeError) as exc:
        return {"status": "error", "error": str(exc)}
    except Exception as exc:  # noqa: BLE001 - verification should report, not raise
        return {"status": "error", "error": f"Unexpected error: {exc}"}


async def _safe_read_debug_console(limit: int, *, clear: bool) -> dict:
    try:
        result = await read_debug_console(limit=limit, clear=clear)
        return {"status": "ok", "result": result}
    except (BridgeConnectionError, BridgeTimeoutError, BridgeError) as exc:
        return {"status": "error", "error": str(exc)}
    except Exception as exc:  # noqa: BLE001 - verification should report, not raise
        return {"status": "error", "error": f"Unexpected error: {exc}"}


async def _safe_run(scene: str, timeout: float, project_root: str | Path | None) -> dict:
    try:
        return {
            "status": "ok",
            "result": await run(
                action="play",
                scene=scene,
                timeout=timeout,
                project_root=project_root,
            ),
        }
    except BridgeError as exc:
        return {"status": "error", "code": exc.code, "error": exc.error_message}
    except (BridgeConnectionError, BridgeTimeoutError) as exc:
        return {"status": "error", "error": str(exc)}
    except Exception as exc:  # noqa: BLE001 - verification should report, not raise
        return {"status": "error", "error": f"Unexpected error: {exc}"}


async def _safe_stop() -> dict:
    try:
        return {"status": "ok", "result": await run(action="stop")}
    except Exception as exc:  # noqa: BLE001 - stop failure should not hide verdict
        return {"status": "error", "error": str(exc)}


def _failing_entries(entries: list[dict], *, fail_on_warnings: bool) -> list[dict]:
    failures: list[dict] = []
    for entry in entries:
        severity = str(entry.get("severity", "error")).lower()
        if severity in _FAIL_SEVERITIES or (fail_on_warnings and severity == "warning"):
            failures.append(entry)
    return failures


def _warning_entries(entries: list[dict]) -> list[dict]:
    return [
        entry
        for entry in entries
        if str(entry.get("severity", "")).lower() == "warning"
    ]


def _verdict(
    verdict: str,
    phase: str,
    scene: str,
    checks: dict,
    notes: list[str],
    summary: str,
    *,
    errors: list | None = None,
    next_action: str = "",
) -> dict:
    result = {
        "verdict": verdict,
        "phase": phase,
        "scene": scene,
        "summary": summary,
        "checks": checks,
        "notes": notes,
    }
    if errors:
        result["errors"] = errors
    if next_action:
        result["next_action"] = next_action
    return result
