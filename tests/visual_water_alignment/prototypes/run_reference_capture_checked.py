"""Run one reference capture and reject logged shader/script errors.

The Godot capture script can print PASS after a shader compilation failure,
so process exit status and its PASS line are insufficient evidence by themselves.
Pass prototype capture options after a standalone ``--``.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time


PROJECT = Path(__file__).resolve().parents[3]
CAPTURE = "res://tests/visual_water_alignment/prototypes/capture_reference.gd"
ERROR_PATTERN = re.compile(r"SCRIPT ERROR|SHADER ERROR|(^|\n)ERROR:|FAIL:", re.I)


def require(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def log_is_clean(output: str, case: str, tick: int, exit_code: int) -> bool:
    return exit_code == 0 and ERROR_PATTERN.search(output) is None and \
        f"PASS: WR reference prototype {case} tick={tick}" in output


def check_file(path_string: str, output_dir: Path, run_id: str,
               started_ns: int) -> Path:
    path = Path(path_string).resolve()
    require(path.is_relative_to(output_dir), f"artifact outside output: {path}")
    require(path.name.startswith(run_id + "_"), f"artifact lacks run_id: {path}")
    require(path.is_file() and path.stat().st_size > 0, f"artifact absent: {path}")
    require(path.stat().st_mtime_ns >= started_ns - 1_000_000_000,
            f"artifact stale: {path}")
    return path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--case", choices=("water", "coupled"), required=True)
    parser.add_argument("--tick", type=int, required=True)
    parser.add_argument("--expected-revision", type=int)
    parser.add_argument("capture_args", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    output_dir = args.output.resolve()
    require(args.godot.is_file() and output_dir.is_dir(), "Godot or output missing")
    require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{2,80}", args.run_id) is not None,
            "invalid run_id")
    require(args.tick >= 1, "invalid tick")
    require(args.expected_revision is None or args.expected_revision >= 0,
            "invalid expected revision")
    require(not list(output_dir.glob(args.run_id + "_*")), "run_id already exists")
    extra = args.capture_args
    if extra and extra[0] == "--":
        extra = extra[1:]
    require(not any(x.startswith(("--output=", "--run-id=", "--case=", "--tick="))
                    for x in extra), "duplicate capture identity option")
    command = [str(args.godot.resolve()), "--path", str(PROJECT),
               "--rendering-driver", "d3d12", "--fullscreen", "--resolution",
               "1920x1080", "--disable-vsync", "--script", CAPTURE, "--",
               f"--case={args.case}", f"--output={output_dir}",
               f"--run-id={args.run_id}", f"--tick={args.tick}",
               "--require-1080p", *extra]
    started_ns = time.time_ns()
    result = subprocess.run(command, cwd=PROJECT, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True,
                            encoding="utf-8", errors="replace", check=False)
    log_path = output_dir / f"{args.run_id}_{args.case}.log"
    log_path.write_text(result.stdout, encoding="utf-8")
    require(log_is_clean(result.stdout, args.case, args.tick, result.returncode),
            f"Godot process or shader/script error: {log_path}")
    manifest_path = output_dir / f"{args.run_id}_{args.case}_manifest.json"
    check_file(str(manifest_path), output_dir, args.run_id, started_ns)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    require(manifest.get("case") == args.case and
            manifest.get("run_id") == args.run_id and
            manifest.get("tick") == args.tick,
            "manifest identity mismatch")
    require(manifest.get("viewport_px") == [1920, 1080] and
            manifest.get("rendering_driver") == "d3d12", "renderer mismatch")
    if args.expected_revision is not None:
        require(manifest.get("revision") == args.expected_revision,
                f"revision mismatch: expected {args.expected_revision}, "
                f"captured {manifest.get('revision')}")
    artifacts = manifest.get("artifacts", [])
    require(len(artifacts) >= 3, "missing camera artifacts")
    checked = [check_file(item, output_dir, args.run_id, started_ns)
               for item in artifacts]
    verified = {
        "role": "reference_capture_checked",
        "run_id": args.run_id, "case": args.case, "tick": args.tick,
        "expected_revision": args.expected_revision,
        "verified_utc": datetime.now(timezone.utc).isoformat(),
        "capture_script_sha256": sha(PROJECT / CAPTURE.removeprefix("res://")),
        "log": str(log_path), "log_sha256": sha(log_path),
        "manifest": str(manifest_path), "manifest_sha256": sha(manifest_path),
        "artifacts_sha256": {str(path): sha(path) for path in checked},
    }
    path = output_dir / f"{args.run_id}_{args.case}_verification.json"
    path.write_text(json.dumps(verified, ensure_ascii=False, indent=2) + "\n",
                    encoding="utf-8")
    print(f"PASS: checked reference capture {args.case} tick={args.tick}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        print(f"FAIL: checked reference capture {exc}", file=sys.stderr)
        sys.exit(1)
