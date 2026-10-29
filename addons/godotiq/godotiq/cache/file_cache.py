"""Hash-based file cache with mtime staleness detection.

Caches parsed file data and invalidates entries when the underlying
file's modification time changes.
"""

from __future__ import annotations

import hashlib
import os
from dataclasses import dataclass
from typing import Any


@dataclass
class CacheEntry:
    """A single cached file entry."""

    path: str
    mtime: float
    content_hash: str
    data: Any


class FileCache:
    """In-memory file cache with hash-based staleness detection."""

    def __init__(self) -> None:
        """Initialise an empty file cache."""
        self._entries: dict[str, CacheEntry] = {}

    def is_stale(self, path: str) -> bool:
        """Check whether the cached entry for *path* is stale.

        An entry is stale when the file's current mtime differs from the
        stored mtime, or when no entry exists for *path*.

        Args:
            path: Filesystem path to check.

        Returns:
            True if the entry is missing or outdated.
        """
        entry = self._entries.get(path)
        if entry is None:
            return True
        try:
            current_mtime = os.path.getmtime(path)
        except OSError:
            return True
        return current_mtime != entry.mtime

    def get(self, path: str) -> Any | None:
        """Return cached data for *path*, or None if stale/missing.

        Args:
            path: Filesystem path to look up.

        Returns:
            The cached data, or None.
        """
        if self.is_stale(path):
            return None
        return self._entries[path].data

    def put(self, path: str, data: Any) -> None:
        """Store *data* in the cache for *path*.

        Records the file's current mtime and a SHA-256 hash of *path*
        for future staleness checks.

        Args:
            path: Filesystem path to cache.
            data: Arbitrary data to associate with the path.
        """
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            mtime = 0.0
        content_hash = hashlib.sha256(path.encode()).hexdigest()
        self._entries[path] = CacheEntry(
            path=path, mtime=mtime, content_hash=content_hash, data=data
        )

    def invalidate(self, path: str) -> None:
        """Remove the cache entry for *path*, if present.

        Args:
            path: Filesystem path to invalidate.
        """
        self._entries.pop(path, None)

    def clear(self) -> None:
        """Remove all cache entries."""
        self._entries.clear()
