"""Serial display-input evidence, regressions and exact source snapshots."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

from run_presentation import ROOT, ENGINE, FATAL, sha, local

CASES = {key: ("unified_edit_display_probe.gd", key, False) for key in [
    "display_core", "display_capacity", "display_cancel", "display_disabled",
    "display_upload", "display_unknown", "display_fatal", "display_capture_mismatch", "display_mixed"]}
CASES.update({"entry_main": ("unified_edit_gravel_entry_probe.gd", "main", True),
              "entry_geometry": ("unified_edit_gravel_entry_probe.gd", "test1_geometry", True),
              "visual_gravel": ("unified_edit_visuals_probe.gd", "visual_gravel", False),
              "visual_all": ("unified_edit_visuals_probe.gd", "visual_all", False),
              "boundary_main": ("unified_edit_boundary_probe.gd", "boundary_main", False),
              "handoff_boundary": ("unified_edit_handoff_probe.gd", "handoff_boundary", False),
              "normal": ("unified_edit_gpu_probe.gd", "normal", False)})
EXTRA_PINS = []


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cases", nargs="+", choices=CASES, default=list(CASES))
    args = parser.parse_args()
    folder = args.output.resolve();folder.mkdir(parents=True, exist_ok=False)
    pinned = ["tools/unified_edit_pipeline/run_display.py", "tools/unified_edit_pipeline/run_presentation.py",
              "tests/integration/unified_edit_display_probe.gd", "tests/integration/unified_edit_gravel_entry_probe.gd",
              "tests/integration/unified_edit_pointer_probe.gd", "tests/integration/unified_edit_playable_probe.gd",
              "tests/integration/unified_edit_visuals_probe.gd", "tests/integration/unified_edit_restore_probe.gd",
              "tests/integration/unified_edit_gpu_probe.gd", "tests/integration/unified_edit_handoff_probe.gd",
              "tests/integration/unified_edit_boundary_probe.gd"]
    pinned += EXTRA_PINS
    sources = {"res://" + path: sha(ROOT / path) for path in pinned}
    report = {"pass": False, "engine": str(ENGINE), "engine_sha256": sha(ENGINE), "runs": [], "sources": sources}
    try:
        for case in args.cases:
            script, tag, entry = CASES[case]
            target = folder / case;target.mkdir()
            command = [str(ENGINE), "--path", str(ROOT), "--script", "res://tests/integration/" + script,
                       "--quit-after", "14400", "--log-file", str(target / "probe.log"), "--",
                       "--output=" + (target.as_posix() if entry else (target / "probe.json").as_posix()),
                       ("--scene=" if entry else "--case=") + tag]
            with (target / "stdout.txt").open("w", encoding="utf-8") as stream:
                result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, timeout=300)
            path = target / "probe.json"
            data = json.loads(path.read_text("utf-8")) if path.exists() else {}
            clean = all(not FATAL.search((target / name).read_text("utf-8", errors="replace")) for name in ["stdout.txt", "probe.log"])
            passed = result.returncode == 0 and data.get("pass") is True and clean
            report["runs"].append({"case": case, "pass": passed, "exit_code": result.returncode,
                                   "clean_logs": clean, "command": command, "evidence": str(path),
                                   "evidence_sha256": sha(path) if path.exists() else None})
            if not passed:
                raise RuntimeError(case + " failed; original evidence retained")
            observed = data.get("source_hashes", data.get("observations", {}).get("sources", {}))
            for name, digest in observed.items():
                if name in sources and sources[name] != digest:
                    raise RuntimeError("source drift: " + name)
                sources[name] = digest
            print("DISPLAY", case, "passed", flush=True)
        for name, digest in sources.items():
            if sha(local(name)) != digest:
                raise RuntimeError("source changed: " + name)
        archive_path = folder / "sources.zip"
        with zipfile.ZipFile(archive_path, "x", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for name in sorted(sources):archive.write(local(name), name.removeprefix("res://"))
            archive.writestr("evidence/source-index.json", json.dumps(sources, indent=2))
        with zipfile.ZipFile(archive_path) as archive:
            assert archive.testzip() is None
            assert all(hashlib.sha256(archive.read(name.removeprefix("res://"))).hexdigest() == h for name, h in sources.items())
        report.update({"pass": True, "source_zip": str(archive_path), "source_zip_sha256": sha(archive_path)})
    except Exception as error:
        report["error"] = str(error);raise
    finally:
        (folder / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":main()
