"""Build-mode detection from ``godotiq.__version__``.

``is_dev_build()`` is a pure function of the package version string
(PEP 440 pre-release detection). It MUST NOT consult
``GODOTIQ_DEV_KEY`` or any other environment variable. This decoupling
is a security property: a prod wheel with a valid (leaked) dev key set
continues to treat env overrides (``GODOTIQ_POLAR_SANDBOX``,
``GODOTIQ_BUNDLE_URL``, ...) as prod — i.e. ignored.
"""

from __future__ import annotations

import re


_PRERELEASE_RE = re.compile(r"(?:dev|a|alpha|b|beta|rc)\d*", re.IGNORECASE)


def _is_dev_version_string(v: str) -> bool:
    """True iff ``v`` is a PEP 440 pre-release (``dev``, ``a``/``alpha``,
    ``b``/``beta``, ``rc``).

    Examples::

        _is_dev_version_string("0.5.0dev0") -> True
        _is_dev_version_string("0.5.0a1")   -> True
        _is_dev_version_string("0.5.0b2")   -> True
        _is_dev_version_string("0.5.0rc0")  -> True
        _is_dev_version_string("0.5.0")     -> False
        _is_dev_version_string("1.0.0")     -> False
        _is_dev_version_string("0.4.1")     -> False
    """
    return _PRERELEASE_RE.search(v) is not None


def is_dev_build() -> bool:
    """True iff ``godotiq.__version__`` is a PEP 440 pre-release string.

    IMPORTANT: This function does NOT consider ``GODOTIQ_DEV_KEY``. The
    dev key is a separate bypass for ``is_pro()`` only. A prod wheel
    with a valid dev key set continues to treat env overrides as prod —
    i.e. ignored. This decoupling prevents a leaked dev key from
    enabling bundle-URL redirection in production.

    Reads ``godotiq.__version__`` at call time (not import time) so
    ``prod_build`` / ``dev_build`` fixtures that monkeypatch the
    package attribute are observed correctly.
    """
    import godotiq

    return _is_dev_version_string(godotiq.__version__)
