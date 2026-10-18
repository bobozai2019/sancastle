"""Freeze and verify the candidate frontend; formal scene paths stay untouched."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

from run_presentation import ROOT, ENGINE, execute, local, sha


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cases", nargs="+", choices=["main", "test1_capture", "test1_backwash", "test1_geometry", "scene_service", "pointer"],
                        default=["main", "test1_capture", "test1_backwash", "test1_geometry", "scene_service", "pointer"])
    args = parser.parse_args()
    folder = args.output.resolve()
    folder.mkdir(parents=True, exist_ok=False)
    pinned = ["tools/unified_edit_pipeline/run_playable.py", "tools/unified_edit_pipeline/run_presentation.py",
              "tools/unified_edit_pipeline/promote_presentation.py",
              "tests/integration/unified_edit_playable_probe.gd", "tests/integration/unified_edit_scene_service_probe.gd",
              "tests/integration/unified_edit_pointer_probe.gd"]
    sources = {"res://" + path: sha(ROOT / path) for path in pinned}
    report = {"pass": False, "scope": "Candidate frontend only; formal cutover/gravel/continuous preview remain",
              "engine": str(ENGINE), "engine_sha256": sha(ENGINE), "runs": [], "sources": sources}
    try:
        for case in args.cases:
            script = {"scene_service": "unified_edit_scene_service_probe.gd", "pointer": "unified_edit_pointer_probe.gd"}.get(case, "unified_edit_playable_probe.gd")
            run = execute(folder / case, "res://tests/integration/" + script, [] if case in ["scene_service", "pointer"] else ["--scene=" + case])
            report["runs"].append({"case": case, **run})
            if not run["pass"]:
                raise RuntimeError(case + " failed; raw evidence retained")
            data = json.loads(Path(run["evidence"]).read_text("utf-8"))
            for key in ["sources", "main_sources", "capture_sources"]:
                for path, digest in data["observations"].get(key, {}).items():
                    if path in sources and sources[path] != digest:
                        raise RuntimeError("source drift: " + path)
                    sources[path] = digest
            print("PLAYABLE", case, "passed", flush=True)
        for path, digest in sources.items():
            if sha(local(path)) != digest:
                raise RuntimeError("source changed: " + path)
        target = folder / "sources.zip"
        with zipfile.ZipFile(target, "x", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for path in sorted(sources):
                archive.write(local(path), path.removeprefix("res://"))
            archive.writestr("evidence/source-index.json", json.dumps(sources, indent=2))
        with zipfile.ZipFile(target) as archive:
            assert archive.testzip() is None
            assert all(hashlib.sha256(archive.read(path.removeprefix("res://"))).hexdigest() == digest for path, digest in sources.items())
        report.update({"pass": True, "source_zip": str(target), "source_zip_sha256": sha(target)})
    except Exception as error:
        report["error"] = str(error)
        raise
    finally:
        (folder / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
