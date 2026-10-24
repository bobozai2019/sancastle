"""Validate the release PCK in a real window, isolated from loose project files."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "tests/integration/export_startup_probe.gd"
FATAL = re.compile(r"ERROR:|SCRIPT ERROR:|were leaked|was leaked|resources still in use", re.I)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, default=Path("D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"))
    parser.add_argument("--pack", type=Path, default=ROOT / "release/sandcastle.pck")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--smoke", action="store_true", help="skip checkpoint byte comparisons; still verify GPU fill/dig receipts")
    parser.add_argument("--scenes", nargs="+", choices=["main", "test1_geometry"], default=["main", "test1_geometry"])
    args = parser.parse_args()
    destination = args.output.resolve()
    destination.mkdir(parents=True, exist_ok=False)
    engine, pack = args.engine.resolve(strict=True), args.pack.resolve(strict=True)
    with pack.open("rb") as stream:
        pack_hash = hashlib.file_digest(stream, "sha256").hexdigest()
    report = {"pass": False, "engine": str(engine), "pack": str(pack), "pack_sha256": pack_hash, "probe_sha256": hashlib.sha256(PROBE.read_bytes()).hexdigest(), "runs": []}
    try:
        # Starting from ROOT would allow FileAccess to silently read loose files
        # missing from the PCK, falsely passing a broken export.
        with tempfile.TemporaryDirectory(prefix="sandcastle_export_") as isolated:
            for scene in args.scenes:
                folder = destination / scene
                folder.mkdir()
                log = folder / "engine.log"
                command = [str(engine), "--main-pack", str(pack), "--script", str(PROBE), "--log-file", str(log), "--", f"--output={folder.as_posix()}", f"--scene={scene}", "--ignore-parameter-config"]
                if args.smoke or scene != "main":
                    command.append("--smoke")
                with (folder / "stdout.txt").open("w", encoding="utf-8") as stream:
                    result = subprocess.run(command, cwd=isolated, stdout=stream, stderr=subprocess.STDOUT, timeout=300)
                evidence = folder / "report.json"
                document = json.loads(evidence.read_text("utf-8")) if evidence.exists() else {}
                logs = (folder / "stdout.txt").read_text("utf-8", errors="replace") + (log.read_text("utf-8", errors="replace") if log.exists() else "")
                passed = result.returncode == 0 and document.get("pass") is True and not FATAL.search(logs)
                report["runs"].append({"scene": scene, "pass": bool(passed), "exit_code": result.returncode, "command": command, "working_directory": isolated, "report": str(evidence)})
                print(f"EXPORT {scene}: {'PASS' if passed else 'FAIL'}", flush=True)
                if not passed:
                    raise RuntimeError(f"Export validation failed: {scene}; inspect {folder}")
        report["pass"] = True
    finally:
        (destination / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), "utf-8")


if __name__ == "__main__":
    main()
