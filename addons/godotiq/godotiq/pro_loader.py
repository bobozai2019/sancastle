"""Pro bundle lifecycle: verified-archive model with throwaway extraction.

The verified archive is the only trust root. The extracted directory is a
per-process throwaway created via ``tempfile.mkdtemp`` and removed at
shutdown. This closes the TOCTOU gap where an attacker could tamper with a
``.py`` file under a persistent extracted directory while leaving the
archive + manifest pair intact.

On-disk layout under :func:`godotiq.paths.bundle_cache_dir`::

    <cache>/
    ├── godotiq_pro-<ver>.zip              ← verified archive
    ├── godotiq_pro-<ver>.manifest.json    ← sha256 + version bounds
    └── ext-<random>/                      ← per-process extraction (ephemeral)

Startup flow:
 1. :func:`_sweep_stale_extractions` removes ``ext-*`` dirs older than 24h
    that are not owned by the current process.
 2. :func:`_find_compatible_cached_archive` walks the cache for the
    highest-version ``(archive, manifest)`` pair compatible with the
    installed godotiq version.
 3. :func:`_verify_cached_archive` recomputes sha256 and matches it
    against **both** the companion manifest and ``PINNED_BUNDLES``.
 4. On success, extract to a fresh ``tempfile.mkdtemp`` and load.
 5. On failure, delete the bad pair and fall through to download.
 6. On download, honor ``X-Receipt`` (not ``X-License-Key``), verify
    Content-Length and sha256 before persisting.
"""

from __future__ import annotations

import atexit
import base64
import hashlib
import hmac
import importlib
import json
import logging
import os
import re
import shutil
import sys
import tempfile
import time
import zipfile
from pathlib import Path
from typing import Callable

import httpx

from godotiq import __version__, _bundle_hashes, paths
from godotiq.license import is_pro
from godotiq.paths import bundle_cache_dir
from godotiq.urls import BUNDLE_ENDPOINT, resolve_endpoint

logger = logging.getLogger(__name__)

_CONNECT_TIMEOUT = 5   # seconds
_READ_TIMEOUT = 15     # seconds

_STALE_EXTRACTION_AGE_SECONDS: int = 24 * 60 * 60
_EXTRACTION_DIR_PREFIX: str = "ext-"
_MAX_BUNDLE_SIZE: int = 50 * 1024 * 1024  # 50 MB ceiling for download body
_TMP_PREFIX: str = ".tmp-"

# Module-level state
_tool_impls: dict[str, Callable] | None = None
_status: str = "community"
_loaded_bundle_root: Path | None = None
_extraction_tmpdir: Path | None = None
# Short enum-keyed leaf describing why the last bundle load attempt failed,
# or None when the loader has not run yet or completed successfully. Surfaced
# via ``bundle_error_detail()`` and ``license_diagnostic()`` so operators can
# distinguish transient HTTP failures (``download_http_401``) from durable
# misalignment (``hash_mismatch``) without parsing logs.
_last_error_detail: str | None = None


def _reset() -> None:
    """Reset module state. For testing only."""
    global _tool_impls, _status, _loaded_bundle_root, _extraction_tmpdir
    global _last_error_detail
    _tool_impls = None
    _status = "community"
    _loaded_bundle_root = None
    _extraction_tmpdir = None
    _last_error_detail = None


def _set_error_detail(detail: str | None) -> None:
    """Record (or clear, with None) the leaf reason for the last failure."""
    global _last_error_detail
    _last_error_detail = detail


def bundle_error_detail() -> str | None:
    """Return the short enum reason for the last bundle load failure.

    Possible values (kept stable as part of the diagnostic contract):

    - ``receipt_missing``: no receipt envelope on disk.
    - ``download_http_<code>``: Worker returned a non-200 status
      (e.g. ``download_http_401`` for an expired/rejected receipt,
      ``download_http_429`` for rate-limit, ``download_http_404`` for
      no compatible bundle).
    - ``download_network``: connect/timeout error reaching the Worker.
    - ``download_unexpected``: any other exception during the download
      flow (defensive — the loader never raises).
    - ``content_length_invalid``: Content-Length header missing or
      outside ``[0, 50 MB]``.
    - ``content_length_mismatch``: body bytes received differed from the
      header.
    - ``bundle_too_large``: streaming body exceeded the 50 MB cap.
    - ``hash_mismatch``: downloaded bytes did not match any
      ``PINNED_BUNDLES`` entry — release misalignment between PyPI wheel
      and R2 bundle, OR a hostile/corrupted response.
    - ``persist_failed``: write/rename of cached archive failed.
    - ``extract_failed``: zip extraction or structure validation failed.
    - ``load_failed``: ``godotiq_pro.registry`` import failed.
    - ``cached_bundle_unverified``: a previously-cached archive failed
      re-verification at startup (transient; cleared if a fresh download
      succeeds).

    Returns ``None`` when the loader has never run in this process or
    when the bundle is currently loaded (``pro_status() == "active"``).
    """
    return _last_error_detail


def _bundle_url() -> str:
    """Return the Worker bundle endpoint URL, honoring dev-build env override."""
    return resolve_endpoint(BUNDLE_ENDPOINT, "GODOTIQ_BUNDLE_URL")


_PEP440_PRE_SUFFIX_RE = re.compile(
    r"(?i)(a|alpha|b|beta|c|rc|dev|pre|preview|post)\d*$"
)


def _version_tuple(v: str) -> tuple[int, ...]:
    """Parse ``'0.4.0'`` / ``'0.5.0rc1'`` into ``(0, 4, 0)`` / ``(0, 5, 0)``.

    Strips PEP 440 pre-release / dev / post suffixes from the final
    segment so the caller gets a numeric triple suitable for range
    comparison. A prerelease (e.g. ``0.5.0rc1``) collapses to its base
    triple (``0.5.0``) — the rule for bundle compatibility is "within
    min/max bounds of the base version"; pre-release qualifiers do not
    narrow that range.
    """
    clean = v.split("-")[0].split("+")[0]
    parts = clean.split(".")
    out: list[int] = []
    for part in parts:
        stripped = _PEP440_PRE_SUFFIX_RE.sub("", part) or "0"
        try:
            out.append(int(stripped))
        except ValueError:
            out.append(0)
    return tuple(out)


def _is_version_compatible(manifest: dict) -> bool:
    """Check if the current ``__version__`` is within manifest bounds."""
    if __version__ == "0.0.0-dev":
        return True
    current = _version_tuple(__version__)
    min_v = _version_tuple(manifest.get("min_godotiq", "0.0.0"))
    max_v = _version_tuple(manifest.get("max_godotiq", "99.99.99"))
    return min_v <= current <= max_v


def _validate_bundle_structure(extract_dir: Path) -> bool:
    """Check for manifest.json, godotiq_pro/__init__.py, godotiq_pro/registry.py."""
    required = [
        extract_dir / "manifest.json",
        extract_dir / "godotiq_pro" / "__init__.py",
        extract_dir / "godotiq_pro" / "registry.py",
    ]
    return all(f.is_file() for f in required)


def _safe_extract(zf: zipfile.ZipFile, dest: Path) -> None:
    """Extract zip contents, rejecting members that escape the destination."""
    dest = dest.resolve()
    for member in zf.infolist():
        target = (dest / member.filename).resolve()
        if not str(target).startswith(str(dest) + os.sep) and target != dest:
            raise ValueError(f"Zip member escapes destination: {member.filename}")
    zf.extractall(dest)


def _load_bundle(bundle_dir: Path) -> bool:
    """Load a verified bundle into the process.

    Handles sys.path/sys.modules cleanup and imports ``godotiq_pro.registry``.
    Returns True on success. Does NOT set ``_status`` — caller owns
    lifecycle state.
    """
    global _tool_impls, _loaded_bundle_root

    if _loaded_bundle_root is not None:
        root_str = str(_loaded_bundle_root)
        sys.path[:] = [p for p in sys.path if p != root_str]

    for key in list(sys.modules.keys()):
        if key.startswith("godotiq_pro"):
            del sys.modules[key]

    bundle_str = str(bundle_dir)
    sys.path.insert(0, bundle_str)
    _loaded_bundle_root = bundle_dir

    try:
        registry = importlib.import_module("godotiq_pro.registry")
        _tool_impls = registry.TOOL_IMPLS
        return True
    except Exception:
        logger.error("Failed to import godotiq_pro.registry from %s", bundle_dir)
        sys.path[:] = [p for p in sys.path if p != bundle_str]
        _loaded_bundle_root = None
        _tool_impls = None
        return False


def _find_compatible_cached_archive(cache_dir: Path) -> tuple[Path, Path] | None:
    """Return ``(archive_path, manifest_path)`` for the best compatible pair.

    Walks ``cache_dir`` for ``godotiq_pro-<ver>.zip`` paired with
    ``godotiq_pro-<ver>.manifest.json``, picks the highest-version pair whose
    ``min/max_godotiq`` bounds are compatible with ``__version__``. Returns
    None if nothing matches.
    """
    if not cache_dir.exists():
        return None

    best: tuple[Path, Path] | None = None
    best_version: tuple[int, ...] = (0,)

    try:
        entries = list(cache_dir.iterdir())
    except OSError:
        return None

    for entry in entries:
        if not entry.is_file() or not entry.name.endswith(".zip"):
            continue
        if not entry.name.startswith("godotiq_pro-"):
            continue
        stem = entry.name[: -len(".zip")]
        manifest_path = cache_dir / f"{stem}.manifest.json"
        if not manifest_path.is_file():
            continue
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            continue
        if not _is_version_compatible(manifest):
            continue
        try:
            v = _version_tuple(manifest.get("bundle_version", "0.0.0"))
        except ValueError:
            continue
        if v > best_version:
            best = (entry, manifest_path)
            best_version = v

    return best


def _verify_cached_archive(archive_path: Path, manifest_path: Path) -> bool:
    """Verify archive sha256 against **both** manifest and ``PINNED_BUNDLES``.

    Returns False if the manifest is unreadable, the archive is unreadable,
    sha256 != manifest["sha256"], or the computed sha256 is not in
    ``_bundle_hashes.PINNED_BUNDLES``. The self-consistent manifest alone is
    insufficient — the pinned-hash allowlist is the trust root.
    """
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        return False

    manifest_hash = manifest.get("sha256", "")
    if not isinstance(manifest_hash, str) or len(manifest_hash) != 64:
        return False

    try:
        archive_bytes = archive_path.read_bytes()
    except OSError:
        return False

    computed = hashlib.sha256(archive_bytes).hexdigest()
    if not hmac.compare_digest(computed, manifest_hash):
        return False

    return any(
        hmac.compare_digest(entry.get("sha256", ""), computed)
        for entry in _bundle_hashes.PINNED_BUNDLES.values()
    )


def _sweep_stale_extractions(cache_dir: Path) -> None:
    """Remove stale ``ext-*`` dirs and ``.tmp-*`` download artifacts.

    Removes, if older than ``_STALE_EXTRACTION_AGE_SECONDS``:
    - Directories whose name starts with ``_EXTRACTION_DIR_PREFIX`` (crashed
      extraction tempdirs from prior processes), excluding the active
      extraction owned by the current process (``_extraction_tmpdir``).
    - Files whose name starts with ``_TMP_PREFIX`` and ends with ``.zip`` or
      ``.manifest.json`` (download artifacts leaked when a prior download
      was killed between ``write_bytes`` and the atomic ``os.replace``).

    Best-effort: swallows every exception per entry so a broken entry never
    crashes server startup.
    """
    if not cache_dir.exists():
        return

    now = time.time()
    owned = _extraction_tmpdir
    owned_resolved = None
    if owned is not None:
        try:
            owned_resolved = owned.resolve()
        except OSError:
            owned_resolved = None

    try:
        entries = list(cache_dir.iterdir())
    except OSError:
        return

    for entry in entries:
        try:
            name = entry.name
            is_ext_dir = entry.is_dir() and name.startswith(
                _EXTRACTION_DIR_PREFIX
            )
            is_tmp_file = entry.is_file() and name.startswith(_TMP_PREFIX) and (
                name.endswith(".zip") or name.endswith(".manifest.json")
            )
            if not (is_ext_dir or is_tmp_file):
                continue
            if is_ext_dir and owned_resolved is not None:
                try:
                    if entry.resolve() == owned_resolved:
                        continue
                except OSError:
                    pass
            try:
                age = now - entry.stat().st_mtime
            except OSError:
                continue
            if age < _STALE_EXTRACTION_AGE_SECONDS:
                continue
            if is_ext_dir:
                shutil.rmtree(entry, ignore_errors=True)
            else:
                try:
                    entry.unlink()
                except OSError:
                    pass
        except Exception:  # noqa: BLE001 - never raise on startup
            logger.debug(
                "sweep_stale_extractions: error on %s",
                entry,
                exc_info=True,
            )


def _register_extraction_cleanup(tmpdir: Path) -> None:
    """Register an atexit handler to remove ``tmpdir`` at shutdown.

    Also updates module-level ``_extraction_tmpdir``.
    """
    global _extraction_tmpdir
    _extraction_tmpdir = tmpdir

    def _cleanup() -> None:
        shutil.rmtree(tmpdir, ignore_errors=True)

    atexit.register(_cleanup)


def _read_receipt_envelope_b64() -> str | None:
    """Return the on-disk receipt envelope as a base64 string.

    The envelope file bytes are base64-encoded verbatim (matching what the
    Worker's ``/api/pro-bundle`` endpoint expects in ``X-Receipt``). Returns
    None if the receipt is missing, empty, or unreadable.
    """
    try:
        raw = paths.receipt_path().read_bytes()
    except FileNotFoundError:
        return None
    except (IsADirectoryError, PermissionError, OSError) as exc:
        logger.debug("Failed to read receipt envelope: %s", exc)
        return None
    if not raw:
        return None
    return base64.b64encode(raw).decode("ascii")


def _extract_and_load(archive_path: Path, cache_dir: Path) -> bool:
    """Extract archive to a fresh tmpdir under ``cache_dir`` and load it.

    Creates the tmpdir with ``tempfile.mkdtemp(prefix=_EXTRACTION_DIR_PREFIX,
    dir=cache_dir)`` so it is unique per process. Expects the flat archive
    layout produced by ``scripts/build_bundle.py`` (``manifest.json`` +
    ``godotiq_pro/`` at archive root). Registers atexit cleanup on success;
    removes the tmpdir on any failure so no extracted files ever outlive a
    failed load.
    """
    try:
        tmpdir = Path(
            tempfile.mkdtemp(prefix=_EXTRACTION_DIR_PREFIX, dir=str(cache_dir))
        )
    except OSError as exc:
        logger.warning("Failed to create extraction tmpdir: %s", exc)
        return False

    try:
        with zipfile.ZipFile(archive_path) as zf:
            _safe_extract(zf, tmpdir)

        if not _validate_bundle_structure(tmpdir):
            shutil.rmtree(tmpdir, ignore_errors=True)
            return False

        if not _load_bundle(tmpdir):
            shutil.rmtree(tmpdir, ignore_errors=True)
            return False

        _register_extraction_cleanup(tmpdir)
        return True
    except Exception as exc:  # noqa: BLE001 - defensive: never raise to caller
        logger.warning("Extract/load failed: %s", exc)
        shutil.rmtree(tmpdir, ignore_errors=True)
        return False


def _read_body_with_cap(resp: httpx.Response) -> bytes | None:
    """Stream ``resp`` into memory, aborting if the body exceeds
    ``_MAX_BUNDLE_SIZE``.

    Returns the full body bytes on success, or ``None`` if the body is too
    large or a Content-Length header (if present) lies about the size.
    """
    length_header = resp.headers.get("Content-Length", "")
    expected_length: int | None = None
    if length_header:
        try:
            expected_length = int(length_header)
        except ValueError:
            logger.warning(
                "Bundle Content-Length not an integer: %r", length_header
            )
            _set_error_detail("content_length_invalid")
            return None
        if expected_length < 0 or expected_length > _MAX_BUNDLE_SIZE:
            logger.warning(
                "Bundle Content-Length %d outside bounds (max %d)",
                expected_length,
                _MAX_BUNDLE_SIZE,
            )
            _set_error_detail("content_length_invalid")
            return None

    buf = bytearray()
    for chunk in resp.iter_bytes():
        if len(buf) + len(chunk) > _MAX_BUNDLE_SIZE:
            logger.warning(
                "Bundle body exceeded %d bytes during streaming",
                _MAX_BUNDLE_SIZE,
            )
            _set_error_detail("bundle_too_large")
            return None
        buf.extend(chunk)

    if expected_length is not None and len(buf) != expected_length:
        logger.warning(
            "Bundle Content-Length mismatch: header=%d body=%d",
            expected_length,
            len(buf),
        )
        _set_error_detail("content_length_mismatch")
        return None

    return bytes(buf)


def _download_and_install_bundle(cache_dir: Path) -> None:
    """Download bundle via ``X-Receipt``, verify, persist, extract, load.

    On any failure, sets ``_status = "community"`` and returns. Never retries
    beyond a single HTTP call — transient network/hash errors fall back to
    community mode rather than hammering the Worker.

    Body is streamed with a ``_MAX_BUNDLE_SIZE`` cap so a hostile or
    compromised Worker response cannot OOM the client before hash
    verification runs.
    """
    global _status

    receipt_b64 = _read_receipt_envelope_b64()
    if receipt_b64 is None:
        _status = "community"
        _set_error_detail("receipt_missing")
        return

    url = _bundle_url()

    try:
        with httpx.Client(
            timeout=httpx.Timeout(_READ_TIMEOUT, connect=_CONNECT_TIMEOUT)
        ) as client:
            with client.stream(
                "POST",
                url,
                headers={"X-Receipt": receipt_b64},
                json={"godotiq_version": __version__},
            ) as resp:
                if resp.status_code != 200:
                    logger.warning(
                        "Bundle download failed: HTTP %s", resp.status_code
                    )
                    _status = "community"
                    _set_error_detail(f"download_http_{resp.status_code}")
                    return

                bundle_data = _read_body_with_cap(resp)

        if bundle_data is None:
            # _read_body_with_cap already set the specific error_detail
            # (content_length_invalid / content_length_mismatch /
            # bundle_too_large). Don't overwrite it here.
            _status = "community"
            return

        computed = hashlib.sha256(bundle_data).hexdigest()
        matched_version: str | None = None
        matched_entry: dict[str, str] | None = None
        for ver, entry in _bundle_hashes.PINNED_BUNDLES.items():
            if hmac.compare_digest(entry.get("sha256", ""), computed):
                matched_version = ver
                matched_entry = entry
                break

        if matched_entry is None or matched_version is None:
            logger.warning(
                "Downloaded bundle sha256 %s not in PINNED_BUNDLES", computed
            )
            _status = "community"
            _set_error_detail("hash_mismatch")
            return

        archive_path = cache_dir / f"godotiq_pro-{matched_version}.zip"
        manifest_path = (
            cache_dir / f"godotiq_pro-{matched_version}.manifest.json"
        )

        tmp_archive = cache_dir / f"{_TMP_PREFIX}{os.urandom(8).hex()}.zip"
        tmp_manifest = (
            cache_dir / f"{_TMP_PREFIX}{os.urandom(8).hex()}.manifest.json"
        )
        manifest_payload = {
            "bundle_version": matched_version,
            "sha256": computed,
            "min_godotiq": matched_entry.get("min_godotiq", "0.0.0"),
            "max_godotiq": matched_entry.get("max_godotiq", "99.99.99"),
        }
        try:
            tmp_archive.write_bytes(bundle_data)
            tmp_manifest.write_text(
                json.dumps(manifest_payload, sort_keys=True),
                encoding="utf-8",
            )
            os.replace(tmp_archive, archive_path)
            os.replace(tmp_manifest, manifest_path)
        except OSError as exc:
            logger.warning("Failed to persist bundle archive: %s", exc)
            tmp_archive.unlink(missing_ok=True)
            tmp_manifest.unlink(missing_ok=True)
            _status = "community"
            _set_error_detail("persist_failed")
            return

        if _extract_and_load(archive_path, cache_dir):
            _status = "active"
            _set_error_detail(None)
        else:
            _status = "community"
            _set_error_detail("extract_failed")

    except (httpx.ConnectError, httpx.TimeoutException) as exc:
        logger.warning("Bundle download failed: %s", exc)
        _status = "community"
        _set_error_detail("download_network")
    except Exception as exc:  # noqa: BLE001 - defensive: never raise on startup
        logger.error("Unexpected error during bundle download: %s", exc)
        _status = "community"
        _set_error_detail("download_unexpected")


def ensure_pro_bundle() -> None:
    """Called at startup. Loads a verified Pro bundle if licensed. Never raises.

    See module docstring for the full flow. ``pro_status()`` reflects the
    terminal state after this returns.
    """
    global _status

    try:
        if not is_pro():
            _status = "community"
            # Not a bundle failure — there's simply no Pro entitlement to
            # load. Clear any stale detail from a prior process state.
            _set_error_detail(None)
            return

        cache_dir = bundle_cache_dir()
        _sweep_stale_extractions(cache_dir)

        pair = _find_compatible_cached_archive(cache_dir)
        if pair is not None:
            archive_path, manifest_path = pair
            if _verify_cached_archive(archive_path, manifest_path):
                if _extract_and_load(archive_path, cache_dir):
                    _status = "active"
                    _set_error_detail(None)
                    return
                # Load failed — fall through to download. Record the
                # failure but allow the download path to overwrite it
                # with the more specific failure (or clear it on success).
                _set_error_detail("extract_failed")
            else:
                _status = "cached_bundle_unverified"
                _set_error_detail("cached_bundle_unverified")
                archive_path.unlink(missing_ok=True)
                manifest_path.unlink(missing_ok=True)
                # fall through to download

        _status = "download_required"
        _download_and_install_bundle(cache_dir)

    except Exception as exc:  # noqa: BLE001 - startup must not crash server
        logger.error("Failed to initialize Pro bundle: %s", exc)
        _status = "community"
        _set_error_detail("download_unexpected")


def get_pro_implementation(tool_name: str) -> Callable | None:
    """Return the Pro implementation for a tool, or None if not available."""
    if _tool_impls is None:
        return None
    return _tool_impls.get(tool_name)


def pro_status() -> str:
    """Return current Pro bundle status.

    Possible values:
    - ``active``: archive verified and loaded from a throwaway tempdir.
    - ``community``: no license, no receipt, or all verification paths
      failed.
    - ``cached_bundle_unverified``: cached archive failed verification
      (transient; typically upgraded to ``active`` after a successful
      re-download, or ``community`` if download also fails).
    - ``download_required``: transient between finding no verified cache
      and completing the download.
    """
    return _status
