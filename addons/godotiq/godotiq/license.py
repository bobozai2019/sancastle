"""GodotIQ licensing — Pro entitlement via signed Ed25519 receipts.

Trust chain (0.5.0):

1. Client stores ``install_id`` (UUID v4) once per machine.
2. Client POSTs ``{license_key, install_id, godotiq_version}`` to the
   Worker ``/api/activate``. Worker validates with Polar, returns a
   signed envelope ``{"payload": {...}, "sig": "<b64>"}``.
3. Client writes the envelope atomically to ``paths.receipt_path()``
   (0600 perms, managed by :mod:`godotiq.receipt`).
4. Every ``is_pro()`` call verifies the envelope locally using
   Ed25519 pubkeys from :mod:`godotiq._keys`. No network I/O on the
   hot path.
5. Worker-signed ``iat`` is recorded as a high-water mark. A later
   receipt with ``iat < high_water_mark`` is rejected as clock-rollback.

Dev-key bypass: ``GODOTIQ_DEV_KEY`` matching ``_DEV_KEY_HASH`` grants
Pro on any build. This is orthogonal to ``is_dev_build()`` — a valid
dev key on a prod wheel still does NOT re-enable env overrides
(bundle URL, activate URL, receipt URL). See section-04 fencing.

License sources (checked in order):

1. ``GODOTIQ_DEV_KEY`` — SHA-256 hashed dev key.
2. Signed receipt on disk (verified locally every call).
3. Worker ``/api/activate`` — when a license key is set and no valid
   receipt is cached.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import os
import sys
import time
from typing import Any

import httpx

from godotiq import _keys, paths, receipt, urls
from godotiq.receipt import (
    InvalidSignature,
    MalformedReceipt,
    ReceiptError,
    UnknownKid,
)
from godotiq.urls import MANAGE_URL, UPGRADE_URL

logger = logging.getLogger(__name__)

# ── 14 PRO tools (intelligence & analysis) ────────────────────────────

PRO_TOOLS: frozenset[str] = frozenset({
    "godotiq_project_summary",
    "godotiq_file_context",
    "godotiq_dependency_graph",
    "godotiq_validate",
    "godotiq_signal_map",
    "godotiq_trace_flow",
    "godotiq_impact_check",
    "godotiq_animation_audit",
    "godotiq_asset_registry",
    "godotiq_scene_map",
    "godotiq_spatial_audit",
    "godotiq_suggest_scale",
    "godotiq_placement",
    "godotiq_explore",
})

# SHA-256 hash of the dev key (passphrase never stored in source)
_DEV_KEY_HASH = "47a9f2aec934b3a6c5998d43aa8bde3406effbafbc8bef788c66f2bd149ee247"

# Operational telemetry for section-10 godotiq_ping.
# Updated by every branch of is_pro(). Initial value before any call:
_last_status_reason: str = "missing"

# Per-process dedup for noisy warnings (plan §3.7).
_warned_install_ids: set[str] = set()
_warned_kids: set[str] = set()

# Per-process set of install_ids whose seat the Worker has revoked.
# Populated on HTTP 410 during refresh_receipt; consulted by is_pro()
# to refuse grace-window grants even though the receipt file is still
# present (kept for forensics per plan §3.7). Cleared by
# _reset_license_cache() for test isolation.
_revoked_seats: set[str] = set()


def _set_status(reason: str) -> None:
    global _last_status_reason
    _last_status_reason = reason


def last_status_reason() -> str:
    """Return the receipt status leaf from the most recent ``is_pro()`` call.

    Pure read of module state: does NOT trigger a fresh evaluation, does NOT
    touch the network or filesystem. Safe to call from the ping handler
    without causing side effects. Returns ``"missing"`` if ``is_pro()`` has
    not been called this process.

    Returned values: ``missing``, ``active``, ``within_grace``, ``expired``,
    ``not_yet_valid``, ``malformed``, ``unknown_kid``,
    ``install_id_mismatch``, ``clock_rollback_detected``,
    ``key_hash_mismatch``, ``limit_reached``, ``key_revoked``,
    ``network_unreachable``, ``worker_5xx``, ``invalid_license``,
    ``signature_mismatch``, ``unexpected_response``, ``migration_required``.
    """
    return _last_status_reason


def get_license_status() -> str:
    """Back-compat alias for :func:`last_status_reason`.

    Predates section-10 naming. Returns the same value as
    :func:`last_status_reason`; kept so tests and any external callers
    written against the section-08 name continue to work unchanged.
    """
    return last_status_reason()


def _reset_license_cache() -> None:
    """Reset in-process license state. For testing only."""
    _set_status("missing")
    _warned_install_ids.clear()
    _warned_kids.clear()
    _revoked_seats.clear()


def _hash_key(key: str) -> str:
    """SHA-256 hex digest of a license key (never stored in plaintext)."""
    return hashlib.sha256(key.encode("utf-8")).hexdigest()


def _current_version() -> str:
    import godotiq
    return godotiq.__version__


def _warn_once(bucket: set[str], key: str, msg: str, *args: Any) -> None:
    if key in bucket:
        return
    bucket.add(key)
    logger.warning(msg, *args)


def _extract_kid(payload_bytes: bytes) -> str:
    try:
        parsed = json.loads(payload_bytes)
        kid = parsed.get("kid")
        if isinstance(kid, str):
            return kid
    except (ValueError, TypeError, AttributeError):
        pass
    return "<unreadable>"


def _payload_iat(payload_bytes: bytes) -> int | None:
    """Return the iat integer from a receipt payload, or None."""
    try:
        parsed = json.loads(payload_bytes)
        if isinstance(parsed, dict):
            iat = parsed.get("iat")
            if isinstance(iat, int) and not isinstance(iat, bool):
                return iat
    except (ValueError, TypeError):
        pass
    return None


# ── Receipt verification helpers ──────────────────────────────────────

def _parse_envelope(data: dict) -> tuple[bytes, bytes] | None:
    """Extract (canonical payload bytes, sig bytes) from an HTTP body dict.

    The Worker's ``/api/activate`` and ``/api/receipt`` endpoints return
    ``{"receipt": {"payload": {...}, "sig": "<b64>"}}`` (see
    ``worker/src/activate.ts`` and ``worker/src/receipt.ts`` — both call
    ``jsonOk({receipt: envelope}, ...)``). The envelope itself lives one
    level down, NOT at the body root. A 0.5.0rc1 regression read the body
    root directly and silently downgraded every fresh activation to
    ``migration_required``; this function is the single chokepoint that
    enforces the documented wire shape.

    Returns ``None`` if the body is missing the ``receipt`` key, the
    envelope is shape-wrong, or ``sig`` is not well-formed base64 of the
    expected Ed25519 length (64 bytes).
    """
    if not isinstance(data, dict):
        return None
    envelope = data.get("receipt")
    if not isinstance(envelope, dict):
        return None
    payload = envelope.get("payload")
    sig_b64 = envelope.get("sig")
    if not isinstance(payload, dict) or not isinstance(sig_b64, str):
        return None
    try:
        sig = base64.b64decode(sig_b64, validate=True)
    except (ValueError, base64.binascii.Error):
        return None
    if len(sig) != 64:
        return None
    return receipt.canonicalize_payload(payload), sig


def _persist_envelope(payload_bytes: bytes, sig: bytes, iat: int) -> None:
    """Atomic-write receipt.json + advance the high-water mark."""
    receipt.write_receipt_to_disk(paths.receipt_path(), payload_bytes, sig)
    receipt.write_high_water_mark(paths.high_water_mark_path(), iat)


def _retire_legacy_cache_if_present() -> None:
    """One-shot migration cleanup: rename legacy license_cache.json to .legacy."""
    legacy = paths.license_cache_path()
    if not legacy.exists():
        return
    target = legacy.with_name(legacy.name + ".legacy")
    try:
        os.replace(legacy, target)
    except OSError:
        logger.debug("Failed to rename legacy license cache", exc_info=True)


# ── is_pro() decision tree ────────────────────────────────────────────

def is_pro() -> bool:
    """Return True if the current environment has valid Pro entitlement.

    Decision tree (see plan §3.2):

    1. Dev-key bypass: ``GODOTIQ_DEV_KEY`` hashes to ``_DEV_KEY_HASH``.
    2. Verify signed receipt on disk:
       - unknown kid / invalid sig / malformed → fall through.
       - install_id or key_hash mismatch → fall through to reactivate.
       - iat < high_water_mark → clock rollback, fall through.
       - now ≤ exp → active; advance watermark; return True.
       - exp < now ≤ grace_until → within_grace; best-effort refresh;
         return True regardless of refresh outcome.
       - else → expired, fall through.
    3. Fall-through: if a license key is set, attempt activation.
       Otherwise return False with status ``missing``.
    """
    # 1. Dev-key bypass (no disk I/O, no install_id side effect).
    dev_key = os.environ.get("GODOTIQ_DEV_KEY", "").strip()
    if dev_key:
        derived = hashlib.sha256(dev_key.encode("utf-8")).hexdigest()
        if hmac.compare_digest(derived, _DEV_KEY_HASH):
            _set_status("active")
            return True

    license_key = os.environ.get("GODOTIQ_LICENSE_KEY", "").strip()
    now = int(time.time())

    # 2. Attempt to load + verify receipt.
    envelope = receipt.read_receipt_from_disk(paths.receipt_path())
    if envelope is not None:
        payload_bytes, sig = envelope
        install_id = receipt.get_or_create_install_id(paths.install_id_path())
        high_water_mark = receipt.read_high_water_mark(
            paths.high_water_mark_path()
        )
        # Pass the receipt's own iat to verify_receipt so its time gate
        # (now < nbf → NotYetValid, now > exp → Expired) always passes for
        # an otherwise-valid receipt. We do our own time checks below using
        # the real `now`, so we can distinguish expired-past-grace (fall
        # through) from within-grace (return True) from active.
        verify_now = _payload_iat(payload_bytes)
        if verify_now is None:
            verify_now = now
        try:
            r = receipt.verify_receipt(
                payload_bytes, sig, _keys.KID_TO_PUBKEY, verify_now
            )
        except UnknownKid:
            bad_kid = _extract_kid(payload_bytes)
            _warn_once(
                _warned_kids,
                bad_kid,
                "Receipt signed under unknown kid %r; ignoring",
                bad_kid,
            )
            _set_status("unknown_kid")
        except InvalidSignature:
            _set_status("missing")
        except MalformedReceipt:
            _set_status("malformed")
        except ReceiptError:
            _set_status("missing")
        else:
            if r.install_id != install_id:
                _warn_once(
                    _warned_install_ids,
                    r.install_id,
                    "Receipt install_id (%s) does not match local install (%s)",
                    r.install_id,
                    install_id,
                )
                _set_status("install_id_mismatch")
            elif install_id in _revoked_seats:
                # Worker returned 410 on a prior refresh within this process —
                # the seat is revoked. Keep the receipt on disk for forensics
                # (plan §3.7) but refuse to grant Pro on any subsequent call
                # until the process restarts or the env changes. Do NOT fall
                # through to re-activation: the same install_id would just be
                # rejected again and the Worker error budget burns for nothing.
                _set_status("install_id_mismatch")
                return False
            elif r.iat < high_water_mark:
                _set_status("clock_rollback_detected")
            elif license_key and _hash_key(license_key) != r.key_hash:
                _set_status("key_hash_mismatch")
                ok = request_activation(license_key, install_id)
                return ok
            elif now < r.nbf:
                _set_status("not_yet_valid")
            elif now <= r.exp:
                _set_status("active")
                receipt.write_high_water_mark(
                    paths.high_water_mark_path(), r.iat
                )
                return True
            elif receipt.is_within_grace(r, now):
                _set_status("within_grace")
                refresh_receipt(license_key, install_id, r.kid)
                return True
            else:
                _set_status("expired")

    # 3. Fall-through. If a license key is set, attempt activation.
    if license_key:
        install_id = receipt.get_or_create_install_id(paths.install_id_path())
        ok = request_activation(license_key, install_id)
        return ok

    # No license key. Preserve any status set by step 2 (e.g. "expired",
    # "unknown_kid", "install_id_mismatch"). Only set "missing" if there
    # was no receipt on disk at all.
    if envelope is None:
        _set_status("missing")
    return False


# ── Worker calls ──────────────────────────────────────────────────────

_HTTP_TIMEOUT = httpx.Timeout(10.0, connect=10.0)


def _activation_failure_reason(status_code: int, error_code: str) -> str:
    """Map Worker activation failures to user-actionable status leaves."""
    if status_code >= 500:
        return "worker_5xx"
    if status_code in {400, 401, 404} and error_code in {
        "INVALID_LICENSE",
        "KEY_NOT_FOUND",
        "NOT_FOUND",
        "UNKNOWN_LICENSE",
    }:
        return "invalid_license"
    return "unexpected_response"


def request_activation(license_key: str, install_id: str) -> bool:
    """POST to Worker /api/activate; on success, save verified receipt.

    Never raises. Returns False on any failure. Exactly one live call
    per invocation — no retry loop (plan §3.7).
    """
    endpoint = urls.resolve_endpoint(
        urls.ACTIVATE_ENDPOINT, "GODOTIQ_ACTIVATE_URL"
    )
    try:
        resp = httpx.post(
            endpoint,
            json={
                "license_key": license_key,
                "install_id": install_id,
                "godotiq_version": _current_version(),
            },
            timeout=_HTTP_TIMEOUT,
        )
    except (httpx.HTTPError, OSError) as exc:
        logger.info("Activation request failed (network): %s", exc)
        _set_status("network_unreachable")
        logger.info(
            "License migration requires a one-time online check. "
            "Please run GodotIQ with network access once to complete "
            "the upgrade."
        )
        return False

    if resp.status_code == 200:
        try:
            data = resp.json()
        except (ValueError, TypeError):
            _set_status("unexpected_response")
            return False
        parsed = _parse_envelope(data)
        if parsed is None:
            _set_status("unexpected_response")
            return False
        payload_bytes, sig = parsed
        try:
            r = receipt.verify_receipt(
                payload_bytes, sig, _keys.KID_TO_PUBKEY, int(time.time())
            )
        except ReceiptError as exc:
            logger.info("Activation envelope failed verification: %s", exc)
            _set_status("signature_mismatch")
            return False
        _persist_envelope(payload_bytes, sig, r.iat)
        _retire_legacy_cache_if_present()
        _set_status("active")
        return True

    try:
        body = resp.json() if resp.content else {}
        # Worker wire shape (worker/src/errors.ts jsonError):
        #   {"error_code": "<CODE>", "error": "<human message>", ...}
        # Reading body["error"] instead of body["error_code"] was a 0.5.0
        # bug that collapsed both LIMIT_REACHED and KEY_REVOKED into
        # migration_required, leaving paying customers with an actionable
        # Polar-side problem stuck on an unhelpful hint.
        error_code = body.get("error_code") or ""
    except (ValueError, TypeError):
        error_code = ""

    if resp.status_code == 403 and error_code == "LIMIT_REACHED":
        _set_status("limit_reached")
        logger.info(
            "License already activated on maximum allowed devices — "
            "manage at %s or contact support.",
            MANAGE_URL,
        )
    elif resp.status_code == 401 and error_code == "KEY_REVOKED":
        _set_status("key_revoked")
        logger.info("License key revoked; contact support.")
    else:
        reason = _activation_failure_reason(resp.status_code, error_code)
        _set_status(reason)
        logger.info(
            "Activation failed (HTTP %s, code=%s, reason=%s).",
            resp.status_code,
            error_code or "(none)",
            reason,
        )
    return False


def refresh_receipt(
    license_key: str, install_id: str, current_kid: str | None
) -> bool:
    """Best-effort refresh of an in-grace receipt. Swallows all errors.

    Called from inside ``is_pro()`` when the on-disk receipt is within its
    signed grace window. Never blocks or propagates errors — the caller
    has already decided True based on the cached receipt.
    """
    if not license_key:
        return False

    endpoint = urls.resolve_endpoint(
        urls.RECEIPT_ENDPOINT, "GODOTIQ_RECEIPT_URL"
    )
    try:
        resp = httpx.post(
            endpoint,
            json={
                "license_key": license_key,
                "install_id": install_id,
                "godotiq_version": _current_version(),
                "current_kid": current_kid,
            },
            timeout=_HTTP_TIMEOUT,
        )
    except (httpx.HTTPError, OSError) as exc:
        logger.debug("Receipt refresh failed (network): %s", exc)
        return False

    if resp.status_code == 410:
        try:
            body = resp.json() if resp.content else {}
        except (ValueError, TypeError):
            body = {}
        activations = body.get("activations")
        if isinstance(activations, list) and not activations:
            logger.info(
                "Receipt refresh reported no active seats; attempting fresh activation."
            )
            return request_activation(license_key, install_id)
        _set_status("install_id_mismatch")
        _revoked_seats.add(install_id)
        return False

    if resp.status_code != 200:
        logger.debug("Receipt refresh HTTP %s", resp.status_code)
        return False

    try:
        data = resp.json()
    except (ValueError, TypeError):
        return False

    parsed = _parse_envelope(data)
    if parsed is None:
        return False
    payload_bytes, sig = parsed
    try:
        r = receipt.verify_receipt(
            payload_bytes, sig, _keys.KID_TO_PUBKEY, int(time.time())
        )
    except ReceiptError as exc:
        logger.debug("Refresh envelope verification failed: %s", exc)
        return False

    _persist_envelope(payload_bytes, sig, r.iat)
    return True


# ── Preview builders ──────────────────────────────────────────────────

def _preview_project_summary(r: dict) -> tuple[dict, list[str], str]:
    counts = r.get("counts", {})
    autoloads = r.get("autoloads", [])
    preview = {
        "project_name": r.get("project_name", ""),
        "engine": r.get("engine", ""),
        "type": r.get("type", ""),
        "counts": counts,
        "autoloads": [a if isinstance(a, str) else a.get("name", str(a)) for a in autoloads],
    }
    locked = [
        "architecture details",
        "autoload implementation paths",
        "scene dependency tree",
        "key systems analysis",
        "signal health overview",
        "code patterns",
    ]
    scripts = counts.get("scripts", 0)
    scenes = counts.get("scenes", 0)
    n = len(autoloads)
    message = (
        f"Project scanned: {scripts} scripts, {scenes} scenes, "
        f"{n} autoloads. Architecture analysis, signal health, and "
        f"code patterns require Pro."
    )
    return preview, locked, message


def _preview_file_context(r: dict) -> tuple[dict, list[str], str]:
    funcs = len(r.get("public_api", {}).get("functions", r.get("functions", [])))
    signals = len(r.get("signals_defined", []))
    preview: dict[str, Any] = {
        "path": r.get("path", ""),
        "signals_defined": signals,
        "functions": funcs,
    }
    if "class_name" in r:
        preview["class_name"] = r["class_name"]
    if "extends" in r:
        preview["extends"] = r["extends"]
    locked = [
        "public API details",
        "signal connections",
        "dependency chain",
        "reverse dependencies (who imports this)",
        "usage in scenes",
    ]
    path = r.get("path", "unknown")
    message = (
        f"{path}: {funcs} functions, {signals} signals defined. "
        f"Full API, dependencies, and reverse imports require Pro."
    )
    return preview, locked, message


def _preview_dependency_graph(r: dict) -> tuple[dict, list[str], str]:
    direct_deps = len(r.get("direct_dependencies", []))
    refs = len(r.get("referenced_by", []))
    emits = len(r.get("emits_signals", []))
    rating = r.get("impact_rating", "unknown")
    preview = {
        "path": r.get("path", ""),
        "impact_rating": rating,
        "direct_dependencies": direct_deps,
        "referenced_by": refs,
        "emits_signals": emits,
    }
    locked = [
        "full dependency tree",
        "reverse dependency details",
        "signal connection targets",
        "transitive impact chain",
    ]
    message = (
        f"{r.get('path', 'unknown')}: impact {rating}, {direct_deps} direct deps, "
        f"referenced by {refs} files. Full dependency tree and signal targets require Pro."
    )
    return preview, locked, message


def _preview_validate(r: dict) -> tuple[dict, list[str], str]:
    total = r.get("total_issues", 0)
    by_sev = r.get("by_severity", {})
    files_checked = r.get("files_checked", 0)
    preview = {
        "total_issues": total,
        "by_severity": by_sev,
        "files_checked": files_checked,
    }
    locked = [
        "issue details and locations",
        "auto-fix suggestions",
        "convention violations list",
    ]
    errors = by_sev.get("error", 0)
    warnings = by_sev.get("warning", 0)
    message = (
        f"Validation found {total} issues ({errors} errors, {warnings} warnings). "
        f"Issue details and fix suggestions require Pro."
    )
    return preview, locked, message


def _preview_signal_map(r: dict) -> tuple[dict, list[str], str]:
    defined = r.get("total_signals_defined", 0)
    connections = r.get("total_connections", 0)
    orphans = len(r.get("orphans", []))
    preview = {
        "total_signals_defined": defined,
        "total_connections": connections,
        "orphans": orphans,
    }
    locked = [
        "signal-to-handler mapping",
        "orphan signal details",
        "missing signal connections",
        "signal flow diagram",
    ]
    message = (
        f"{defined} signals, {connections} connections, {orphans} orphans found. "
        f"Full signal wiring map and orphan details require Pro."
    )
    return preview, locked, message


def _preview_trace_flow(r: dict) -> tuple[dict, list[str], str]:
    entry = r.get("entry", "unknown")
    steps = r.get("total_steps", 0)
    files = r.get("files_involved", 0)
    failures = len(r.get("failure_points", []))
    preview = {
        "entry": entry,
        "total_steps": steps,
        "files_involved": files,
        "failure_points": failures,
    }
    locked = [
        "step-by-step execution chain",
        "file-to-file flow details",
        "failure point locations and reasons",
        "signal chain path",
    ]
    message = (
        f"Traced '{entry}': {steps} steps across {files} files, "
        f"{failures} failure points. Full execution chain requires Pro."
    )
    return preview, locked, message


def _preview_impact_check(r: dict) -> tuple[dict, list[str], str]:
    risk = r.get("risk", "unknown")
    affected = r.get("total_files_affected", 0)
    callers = len(r.get("callers", []))
    signals = len(r.get("signals_affected", []))
    preview = {
        "path": r.get("path", ""),
        "risk": risk,
        "total_files_affected": affected,
        "callers": callers,
        "signals_affected": signals,
    }
    locked = [
        "affected file list",
        "caller details and locations",
        "signal propagation chain",
        "safe change recommendations",
    ]
    message = (
        f"{r.get('path', 'unknown')}: risk {risk}, {affected} files affected, "
        f"{callers} callers. Affected file list and safe change recommendations require Pro."
    )
    return preview, locked, message


def _preview_animation_audit(r: dict) -> tuple[dict, list[str], str]:
    anims = r.get("total_animations", 0)
    total = r.get("total_issues", 0)
    by_sev = r.get("by_severity", {})
    preview = {
        "total_animations": anims,
        "total_issues": total,
        "by_severity": by_sev,
    }
    locked = [
        "issue details per animation",
        "broken track locations",
        "missing transition list",
        "fix suggestions",
    ]
    message = (
        f"{anims} animations scanned, {total} issues found. "
        f"Issue details and fix suggestions require Pro."
    )
    return preview, locked, message


def _preview_asset_registry(r: dict) -> tuple[dict, list[str], str]:
    total = r.get("total_assets", 0)
    unused = r.get("unused_count", 0)
    raw_cats = r.get("by_category", {})
    cats = {k: len(v) if isinstance(v, list) else v for k, v in raw_cats.items()}
    preview = {
        "total_assets": total,
        "unused_count": unused,
        "by_category": cats,
    }
    locked = [
        "asset file paths",
        "unused asset details",
        "missing reference list",
        "per-asset metadata",
    ]
    message = (
        f"{total} assets cataloged, {unused} unused across {len(cats)} categories. "
        f"Full asset paths and details require Pro."
    )
    return preview, locked, message


def _preview_scene_map(r: dict) -> tuple[dict, list[str], str]:
    total_nodes = r.get("total_nodes", 0)
    bounds = r.get("spatial_summary", {}).get("bounds", {})
    all_nodes = r.get("nodes", [])
    preview_nodes = []
    for node in all_nodes[:5]:
        pn: dict[str, Any] = {
            "name": node.get("name", ""),
            "type": node.get("type", ""),
            "world_position": node.get("world_position", []),
        }
        if "distance_to_focus" in node:
            pn["distance_to_focus"] = node["distance_to_focus"]
        preview_nodes.append(pn)
    preview = {
        "total_nodes": total_nodes,
        "spatial_summary": {"bounds": bounds},
        "nodes": preview_nodes,
    }
    remaining = max(0, total_nodes - 5)
    locked = [
        f"full node list with positions ({remaining} more)",
        "distance matrix",
        "spatial relationships",
        "nearby object queries",
    ]
    message = (
        f"Mapped {total_nodes} nodes in {bounds}. Showing 5 of {total_nodes}. "
        f"Full spatial layout with distances and relationships requires Pro."
    )
    return preview, locked, message


def _preview_spatial_audit(r: dict) -> tuple[dict, list[str], str]:
    total = r.get("total_issues", 0)
    by_sev = r.get("by_severity", {})
    checks = r.get("checks_run", [])
    preview = {
        "total_issues": total,
        "by_severity": by_sev,
        "checks_run": checks,
    }
    locked = [
        "issue details and locations",
        "affected node paths",
        "fix suggestions",
        "overlap/gap specifics",
    ]
    message = (
        f"Spatial audit: {total} issues across {len(checks)} checks. "
        f"Issue locations and fix suggestions require Pro."
    )
    return preview, locked, message


def _preview_suggest_scale(r: dict) -> tuple[dict, list[str], str]:
    tier = r.get("match_tier", "unknown")
    refs = r.get("reference_models", r.get("references", []))
    n = len(refs) if isinstance(refs, list) else refs
    preview: dict[str, Any] = {
        "match_tier": tier,
        "references": n,
    }
    if "target" in r:
        preview["target"] = r["target"]
    locked = [
        "recommended scale values",
        "recommended position",
        "reference model comparison details",
    ]
    message = (
        f"Scale analysis complete, match: {tier}, {n} references. "
        f"Recommended scale and position require Pro."
    )
    return preview, locked, message


def _preview_placement(r: dict) -> tuple[dict, list[str], str]:
    evaluated = r.get("candidates_evaluated", 0)
    suggestions = len(r.get("suggestions", []))
    zones = len(r.get("excluded_zones", []))
    preview = {
        "candidates_evaluated": evaluated,
        "suggestions": suggestions,
        "excluded_zones": zones,
    }
    locked = [
        "placement coordinates",
        "confidence scores",
        "constraint satisfaction details",
        "marker slot matches",
    ]
    message = (
        f"{evaluated} positions evaluated, {suggestions} valid placements found. "
        f"Coordinates and confidence scores require Pro."
    )
    return preview, locked, message


def _preview_explore(r: dict) -> tuple[dict, list[str], str]:
    areas = r.get("areas_inspected", 0)
    positions = r.get("total_screenshots", 0)
    nodes = r.get("total_nodes", 0)
    preview = {
        "areas_found": areas,
        "positions_calculated": positions,
        "total_nodes": nodes,
    }
    locked = ["screenshots", "visual inspection data"]
    message = f"Found {areas} areas with {nodes} nodes. Visual inspection requires Pro."
    return preview, locked, message


_PREVIEW_BUILDERS: dict[str, Any] = {
    "godotiq_project_summary": _preview_project_summary,
    "godotiq_file_context": _preview_file_context,
    "godotiq_dependency_graph": _preview_dependency_graph,
    "godotiq_validate": _preview_validate,
    "godotiq_signal_map": _preview_signal_map,
    "godotiq_trace_flow": _preview_trace_flow,
    "godotiq_impact_check": _preview_impact_check,
    "godotiq_animation_audit": _preview_animation_audit,
    "godotiq_asset_registry": _preview_asset_registry,
    "godotiq_scene_map": _preview_scene_map,
    "godotiq_spatial_audit": _preview_spatial_audit,
    "godotiq_suggest_scale": _preview_suggest_scale,
    "godotiq_placement": _preview_placement,
    "godotiq_explore": _preview_explore,
}


# ── Community preview builder ─────────────────────────────────────────

def build_community_preview(tool_name: str, teaser_data: dict) -> dict:
    """Build a community preview response, regardless of license status.

    Unlike gate_pro(), this function ALWAYS constructs a preview. Used by
    Pro tool stubs when the bundle is unavailable (community mode or degraded state).
    """
    builder = _PREVIEW_BUILDERS.get(tool_name)
    if builder is None:
        return {
            "tier": "community",
            "tool": tool_name,
            "preview": {},
            "locked_sections": ["full analysis"],
            "message": f"{tool_name} analysis complete. Full results require Pro.",
            "upgrade": UPGRADE_URL,
        }

    preview, locked, message = builder(teaser_data)
    return {
        "tier": "community",
        "tool": tool_name,
        "preview": preview,
        "locked_sections": locked,
        "message": message,
        "upgrade": UPGRADE_URL,
    }


# ── License diagnostic + Pro-unavailable response ─────────────────────

# Reasons we expose to operators when the user explicitly opted in to Pro
# (key configured) but Pro entitlement is not currently usable. Mirrors
# ``last_status_reason`` enum plus an extra ``bundle_unavailable`` leaf
# for the "receipt active but Pro bundle never loaded" branch.
_REASON_HINTS: dict[str, str] = {
    "missing": (
        "No signed receipt on disk yet. The first request after configuring "
        "GODOTIQ_LICENSE_KEY needs network access to activate."
    ),
    "migration_required": (
        "Legacy activation migration did not complete. Update GodotIQ, run once "
        "with network access, then contact support if it persists."
    ),
    "network_unreachable": (
        "Could not reach the GodotIQ licensing service. Check network access, "
        "VPN/proxy/firewall settings, then restart your MCP client."
    ),
    "worker_5xx": (
        "The GodotIQ licensing service returned a temporary server error. "
        "Retry shortly; if it persists, contact support with auth status --json."
    ),
    "invalid_license": (
        "The configured GODOTIQ_LICENSE_KEY was not accepted. Check the key in "
        "your MCP env block and make sure it matches your Polar purchase."
    ),
    "signature_mismatch": (
        "The signed license receipt could not be verified. Update GodotIQ; if "
        "the error persists, contact support."
    ),
    "unexpected_response": (
        "The licensing service returned an unexpected response. Update GodotIQ "
        "and contact support if this persists."
    ),
    "expired": (
        "Cached receipt past its grace window. Run once online to refresh."
    ),
    "key_revoked": (
        "License key has been revoked. Contact support or check your subscription."
    ),
    "limit_reached": (
        "License already activated on the maximum number of devices. "
        f"Manage seats at {MANAGE_URL}."
    ),
    "key_hash_mismatch": (
        "GODOTIQ_LICENSE_KEY changed since the cached receipt was issued. "
        "Re-activation will run on the next request."
    ),
    "install_id_mismatch": (
        "This device is no longer activated for the configured license. "
        f"Run `godotiq auth reset --yes`, restart your MCP client, or manage seats at {MANAGE_URL}."
    ),
    "unknown_kid": (
        "Cached receipt was signed by a key this client does not trust. "
        "Update godotiq to pick up rotated signing keys."
    ),
    "malformed": (
        "Cached receipt is malformed; delete it and re-activate."
    ),
    "clock_rollback_detected": (
        "System clock has moved backwards since the last receipt. "
        "Verify NTP / system time."
    ),
    "not_yet_valid": (
        "Receipt nbf is in the future. Verify system clock."
    ),
    "bundle_unavailable": (
        "License is active but the Pro bundle could not be loaded. "
        "Re-run with network access; check logs for download/verification "
        "errors."
    ),
}


def license_diagnostic() -> dict:
    """Return a snapshot of license + bundle state for ping / CLI status.

    Single source of truth for surfacing what's wrong (and what's right).
    Calls ``is_pro()`` exactly once — which has well-defined side effects
    (may trigger an activation HTTP call, may persist a receipt). Designed
    so ``godotiq_ping`` and any future ``godotiq auth status`` command can
    share the same payload without double-evaluating the decision tree.

    Keys:
      - ``tier``: ``"pro"`` or ``"community"`` (mirrors current ping field).
      - ``receipt``: receipt status leaf (mirrors current ping field).
      - ``bundle``: pro_loader status (``"active"``, ``"community"``, ...).
      - ``license_key_configured``: True if env var is set non-empty.
      - ``dev_key_configured``: True if dev key env var is set non-empty.
      - ``ok``: True iff the user is genuinely entitled (community without
        a key counts as "ok"; key + non-pro tier counts as NOT ok).
      - ``reason`` (only when not ok): short enum leaf — receipt status, or
        ``"bundle_unavailable"`` when receipt is active but bundle isn't.
      - ``hint`` (only when not ok): one-sentence operator-readable hint.
    """
    has_key = bool(os.environ.get("GODOTIQ_LICENSE_KEY", "").strip())
    has_dev_key = bool(os.environ.get("GODOTIQ_DEV_KEY", "").strip())
    is_pro_now = is_pro()
    receipt_status = last_status_reason()

    # Defer pro_loader import: license.py is imported by pro_loader, so a
    # top-level import would create a cycle.
    from godotiq.pro_loader import bundle_error_detail, pro_status
    bundle_state = pro_status()
    error_detail = bundle_error_detail()

    out: dict[str, Any] = {
        "tier": "pro" if is_pro_now else "community",
        "godotiq_version": _current_version(),
        "python_version": sys.version.split()[0],
        "receipt": receipt_status,
        "bundle": bundle_state,
        "license_key_configured": has_key,
        "dev_key_configured": has_dev_key,
    }
    # Surface the specific bundle failure leaf when known (e.g.
    # "download_http_401", "hash_mismatch"). Operators reading the JSON
    # diagnostic — or support reading a customer-pasted output — can
    # distinguish a worker-side rejection from a release misalignment
    # without needing log access. Omitted entirely when the loader has
    # not run or completed successfully (None).
    if error_detail is not None:
        out["bundle_error_detail"] = error_detail

    # The user is "ok" iff one of:
    # - Pro entitlement is fully usable (receipt valid AND bundle loaded), OR
    # - The user is a legitimate Community user (no key configured AND
    #   is_pro() returned False).
    # "is_pro True but bundle != active" counts as NOT ok even when no key
    # is configured: a stale receipt or dev-key bypass with a broken bundle
    # still produces silently-degraded Pro tools, which is exactly what
    # this contract is here to surface.
    pro_intent = has_key or has_dev_key
    fully_pro = is_pro_now and bundle_state == "active"
    out["ok"] = fully_pro or (not pro_intent and not is_pro_now)

    if not out["ok"]:
        if not is_pro_now:
            reason = receipt_status
        else:
            # is_pro is True but bundle didn't load (download failed,
            # hash mismatch, extract failed, ...).
            reason = "bundle_unavailable"
        out["reason"] = reason
        out["hint"] = _REASON_HINTS.get(
            reason,
            "Pro entitlement is not currently usable. Check logs for details.",
        )
        out["manage"] = MANAGE_URL
        out["upgrade"] = UPGRADE_URL

    return out


def pro_unavailable_response(tool_name: str, teaser_data: dict) -> dict:
    """Pro tool fallback when no Pro implementation is loaded.

    Replaces the unconditional ``build_community_preview`` call inside
    Pro stubs. The contract is now:

    - **No license key configured** → community preview (legitimate
      community user; preview is the right UX).
    - **License key configured but Pro entitlement is not usable**
      (activation failed, receipt expired/revoked, bundle failed to
      load, ...) → explicit error response with a non-empty ``error``
      key, the receipt status leaf, and an actionable hint. NEVER a
      silent community preview — a paying customer must be told why
      their tools aren't working.

    The error shape includes ``"error"`` so downstream gating
    (:func:`gate_pro`) treats it as a passthrough error rather than
    re-wrapping it as a preview.
    """
    state = license_diagnostic()
    if state["ok"]:
        return build_community_preview(tool_name, teaser_data)

    reason = state.get("reason", "missing")
    hint = state.get("hint", "")
    return {
        "tier": "license_error",
        "tool": tool_name,
        "license_state": reason,
        "license_key_configured": state["license_key_configured"],
        "bundle": state["bundle"],
        "error": (
            f"Pro tool '{tool_name}' unavailable: {reason}. {hint}"
        ).strip(),
        "manage": MANAGE_URL,
        "upgrade": UPGRADE_URL,
    }


# ── Gate function ─────────────────────────────────────────────────────

def gate_pro(tool_name: str, result: dict) -> dict:
    """Gate a PRO tool result.  Returns result as-is for PRO users.

    For Community users, discards the full result and returns a rich
    preview dict with real data subsets and locked section names.

    Error results (containing "error" key) always pass through ungated
    so Community users still see actionable error messages.
    """
    if tool_name not in PRO_TOOLS:
        return result

    if is_pro():
        return result

    if "error" in result:
        return result

    builder = _PREVIEW_BUILDERS.get(tool_name)
    if builder is None:
        return {
            "tier": "community",
            "tool": tool_name,
            "preview": {},
            "locked_sections": ["full analysis"],
            "message": f"{tool_name} analysis complete. Full results require Pro.",
            "upgrade": UPGRADE_URL,
        }

    preview, locked, message = builder(result)
    return {
        "tier": "community",
        "tool": tool_name,
        "preview": preview,
        "locked_sections": locked,
        "message": message,
        "upgrade": UPGRADE_URL,
    }
