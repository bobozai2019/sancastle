#!/usr/bin/env python3
"""Verify the main presentation manifest against worktree or staged bytes."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = "assets/unified_edit/presentation/main.json"


def read_staged(relative: str) -> bytes:
    result = subprocess.run(
        ["git", "show", f":{relative}"],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode:
        raise ValueError(f"{relative} is not present in the Git index")
    return result.stdout


def read_worktree(relative: str) -> bytes:
    path = ROOT.joinpath(*PurePosixPath(relative).parts)
    if not path.is_file():
        raise ValueError(f"missing file: {relative}")
    return path.read_bytes()


def verify(staged: bool) -> list[str]:
    read = read_staged if staged else read_worktree
    document = json.loads(read(MANIFEST))
    metadata = document["metadata"]
    artifacts = [("scene", metadata["scene"]), ("seed", metadata["seed"])]
    artifacts.extend(
        (f"material shader {index}", {"path": material["shader"], "sha256": material["shader_sha256"]})
        for index, material in enumerate(metadata["materials"])
    )

    errors = []
    for label, item in artifacts:
        resource_path = item["path"]
        if not resource_path.startswith("res://"):
            errors.append(f"{label}: expected a res:// path, got {resource_path}")
            continue
        relative = resource_path.removeprefix("res://")
        try:
            actual = hashlib.sha256(read(relative)).hexdigest()
        except (OSError, ValueError) as error:
            errors.append(f"{label}: {error}")
            continue
        expected = item["sha256"]
        if actual != expected:
            errors.append(f"{label}: {relative} expected {expected}, got {actual}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", action="store_true", help="validate Git index bytes")
    args = parser.parse_args()
    try:
        errors = verify(args.staged)
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        print(f"main presentation hash check failed: {error}", file=sys.stderr)
        return 1
    if errors:
        print("main presentation hash check failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    scope = "staged" if args.staged else "worktree"
    print(f"main presentation hashes match ({scope})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
