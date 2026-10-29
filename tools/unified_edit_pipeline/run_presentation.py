"""Serial real-window extraction/publication checks; each run uses a fresh path."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[2]
ENGINE = Path("D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe")
SCENES = {"main": "res://scenes/main.tscn", **{
    key: f"res://scenes/playable/{key}.tscn"
    for key in ("test1_geometry")}}
FATAL = re.compile(r"ERROR:|SCRIPT ERROR:|were leaked|was leaked|Stray Node:|resources still in use|ObjectDB instances were leaked", re.I)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def local(path: str) -> Path:
    return ROOT / path.removeprefix("res://") if path.startswith("res://") else Path(path)


def execute(folder: Path, script: str, arguments: list[str]) -> dict:
    folder.mkdir()
    command = [str(ENGINE), "--path", str(ROOT), "--script", script,
               "--quit-after", "10800", "--log-file", str(folder / "probe.log"),
               "--", f"--output={folder.as_posix()}", *arguments]
    with (folder / "stdout.txt").open("w", encoding="utf-8") as stream:
        result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, timeout=240)
    evidence = folder / ("bake.json" if script.endswith("bake_presentation.gd") else "probe.json")
    document = json.loads(evidence.read_text(encoding="utf-8")) if evidence.exists() else {}
    logs = [(folder / "stdout.txt").read_text(encoding="utf-8", errors="replace")]
    if (folder / "probe.log").exists():
        logs.append((folder / "probe.log").read_text(encoding="utf-8", errors="replace"))
    return {"pass": result.returncode == 0 and document.get("pass") is True and
            not any(FATAL.search(log) for log in logs), "exit_code": result.returncode,
            "command": command, "evidence": str(evidence), "evidence_sha256": sha(evidence) if evidence.exists() else None,
            "clean_logs": not any(FATAL.search(log) for log in logs)}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--scenes", nargs="+", choices=SCENES, default=list(SCENES))
    args = parser.parse_args()
    destination = args.output.resolve()
    destination.mkdir(parents=True, exist_ok=False)
    report = {"pass": False, "scope": "Offline presentation, actual material ownership/native restore; no UI or formal cutover",
              "engine": str(ENGINE), "engine_sha256": sha(ENGINE), "runs": [], "sources": {}}
    sources = report["sources"]
    for relative in ("tools/unified_edit_pipeline/run_presentation.py", "tools/unified_edit_pipeline/bake_presentation.gd",
                     "scripts/simulation/unified_edit/presentation.gd", "tests/integration/unified_edit_presentation_probe.gd"):
        sources["res://" + relative] = sha(ROOT / relative)
    try:
        for key in args.scenes:
            bake = execute(destination / (key + "_bake"), "res://tools/unified_edit_pipeline/bake_presentation.gd", [f"--scene={SCENES[key]}"])
            report["runs"].append({"scene": key, "phase": "bake", **bake})
            if not bake["pass"]:
                raise RuntimeError(f"{key} extraction failed; original logs retained")
            manifest = json.loads(Path(bake["evidence"]).read_text(encoding="utf-8"))
            for path, digest in manifest["metadata"]["configuration"]["sources"].items():
                if path in sources and sources[path] != digest:
                    raise RuntimeError(f"source drift: {path}")
                sources[path] = digest
            runtime = execute(destination / (key + "_runtime"), "res://tests/integration/unified_edit_presentation_probe.gd",
                              [f"--manifest={Path(bake['evidence']).as_posix()}"])
            report["runs"].append({"scene": key, "phase": "runtime", **runtime})
            if not runtime["pass"]:
                raise RuntimeError(f"{key} runtime failed; original logs retained")
            for path, digest in json.loads(Path(runtime["evidence"]).read_text(encoding="utf-8"))["sources"].items():
                if path in sources and sources[path] != digest:
                    raise RuntimeError(f"source drift: {path}")
                sources[path] = digest
            print(f"PRESENTATION {key} passed", flush=True)
        for path, digest in sources.items():
            if sha(local(path)) != digest:
                raise RuntimeError(f"source changed during run: {path}")
        archive_path = destination / "sources.zip"
        with zipfile.ZipFile(archive_path, "x", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for path in sorted(sources):
                archive.write(local(path), path.removeprefix("res://"))
            archive.writestr("evidence/source-index.json", json.dumps(sources, indent=2))
        with zipfile.ZipFile(archive_path) as archive:
            assert archive.testzip() is None
            assert all(hashlib.sha256(archive.read(p.removeprefix("res://"))).hexdigest() == h for p, h in sources.items())
        report.update({"pass": True, "source_zip": str(archive_path), "source_zip_sha256": sha(archive_path)})
    except Exception as error:
        report["error"] = str(error)
        raise
    finally:
        (destination / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
