"""Single source of truth for every external URL GodotIQ references.

Every string literal matching the GodotIQ public surface
(``godotiq.com``, ``pro.godotiq.com``, ``github.com/salvo10f/godotiq``)
is consolidated here. Section 03's AST-based test enforces that no
other module under ``src/godotiq/`` contains a raw URL literal to
these hosts.

:func:`resolve_endpoint` honors the named env override only in dev
builds. In prod builds it returns the default and logs once per env var
per process. Callers needing the same log-once semantics for non-URL
overrides can reuse :func:`_log_ignored_override_once`.
"""

from __future__ import annotations

import logging
import os
import threading

from godotiq import _build


UPGRADE_URL: str = "https://godotiq.com/pro"
DOCS_URL: str = "https://godotiq.com/docs"
MANAGE_URL: str = "https://godotiq.com/manage"
REPO_URL: str = "https://github.com/salvo10f/godotiq"
ISSUES_URL: str = "https://github.com/salvo10f/godotiq/issues"

BUNDLE_ENDPOINT: str = "https://pro.godotiq.com/api/pro-bundle"
RECEIPT_ENDPOINT: str = "https://pro.godotiq.com/api/receipt"
ACTIVATE_ENDPOINT: str = "https://pro.godotiq.com/api/activate"

_LOG = logging.getLogger(__name__)

# Module-level dedup set: each env var name is logged at most once per
# process. Tests clear this via an autouse fixture. Guarded by
# ``_LOGGED_OVERRIDES_LOCK`` so a concurrent MCP startup burst doesn't
# race the check-then-add and emit duplicate INFO lines.
_LOGGED_OVERRIDES: set[str] = set()
_LOGGED_OVERRIDES_LOCK = threading.Lock()


def _log_ignored_override_once(env_var: str) -> None:
    """Log one INFO line per process for an ignored env override in a
    prod build. Safe to call repeatedly — subsequent calls with the same
    ``env_var`` are no-ops.

    Exposed so non-URL overrides (e.g. ``GODOTIQ_POLAR_SANDBOX`` used as a
    boolean flip in :mod:`godotiq.license`) share the same dedup state as
    :func:`resolve_endpoint`.
    """
    with _LOGGED_OVERRIDES_LOCK:
        if env_var in _LOGGED_OVERRIDES:
            return
        _LOGGED_OVERRIDES.add(env_var)
    _LOG.info(
        "ignoring %s in prod build — env overrides honored only in dev builds",
        env_var,
    )


def resolve_endpoint(default_url: str, override_env_var: str) -> str:
    """Return endpoint honoring the named env var only in dev builds.

    - Env var unset / empty → ``default_url``, no log.
    - Dev build (``_build.is_dev_build() == True``) → override value.
    - Prod build → ``default_url``; emits one INFO log line per
      ``override_env_var`` per process.
    """
    override = os.environ.get(override_env_var, "").strip()
    if not override:
        return default_url

    if _build.is_dev_build():
        return override

    _log_ignored_override_once(override_env_var)
    return default_url
