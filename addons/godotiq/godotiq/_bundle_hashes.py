"""Pinned bundle hashes for Pro bundle verification.

This is a data-only module. Each entry maps a bundle version to its
SHA-256 hash and compatible godotiq version range.

The build script (scripts/build_bundle.py) generates pinned-hash fragments
that are copied into this file at release time. Do NOT hand-edit entries —
they are build artifacts.

Structure:
    PINNED_BUNDLES = {
        "<bundle_version>": {
            "sha256": "<64-char lowercase hex>",
            "min_godotiq": "<minimum compatible godotiq version>",
            "max_godotiq": "<maximum compatible godotiq version>",
        },
    }
"""

from __future__ import annotations

PINNED_BUNDLES: dict[str, dict[str, str]] = {
    "0.5.4": {
        "sha256": "85ddd6ed7dec37f6c5ceb5951238e3f083c3f1349de5ed18f3ce4c25a0a6d60c",
        "min_godotiq": "0.5.4",
        "max_godotiq": "0.5.4",
    },
    "0.4.0": {
        "sha256": "9d18bbe99f8e4335aa8ebec65065c4efd6bba9286717426c054d0cba9f3900cb",
        "min_godotiq": "0.4.0",
        "max_godotiq": "0.4.99",
    },
}
