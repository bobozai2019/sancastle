"""Run one visible Godot baseline at a time and archive its exact source identity."""
import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--project", required=True)
parser.add_argument("--name", required=True)
parser.add_argument("--origin", default="")
parser.add_argument("--archive", required=True)
parser.add_argument("--binary", default="D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe")
args = parser.parse_args()
project = Path(args.project).resolve()
run = project / "test_output/physics_threading" / args.name
run.mkdir(parents=True, exist_ok=True)
command = [args.binary, "--path", str(project), "--script", "res://tools/physics_threading/baseline_probe.gd",
           "--", "--output=res://test_output/physics_threading/" + args.name, "--detailed"]
if args.origin:
    command.append("--origin=" + args.origin)
identity = {}
for folder in ["scripts", "scenes", "shaders", "assets", "tools/physics_threading"]:
    for file in (project / folder).rglob("*"):
        if file.is_file():
            identity[file.relative_to(project).as_posix()] = hashlib.sha256(file.read_bytes()).hexdigest()
identity["project.godot"] = hashlib.sha256((project / "project.godot").read_bytes()).hexdigest()
(run / "manifest.json").write_text(json.dumps({"command": command, "source": identity,
    "binary_sha256": hashlib.sha256(Path(args.binary).read_bytes()).hexdigest()}, indent=2), encoding="utf-8")
with (run / "runtime.log").open("w", encoding="utf-8") as log:
    process = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=240)
changed = [name for name, digest in identity.items()
           if hashlib.sha256((project / name).read_bytes()).hexdigest() != digest]
(run / "exit.json").write_text(json.dumps({"exit": process.returncode, "source_changes": changed}, indent=2))
if (run / "trace.json").exists():
    trace = json.loads((run / "trace.json").read_text(encoding="utf-8"))
    (run / "effective_config.json").write_text(json.dumps(trace["configuration"], indent=2), encoding="utf-8")
    (run / "commands.json").write_text(json.dumps({c["name"]: c["inputs"] for c in trace["cases"]}, indent=2), encoding="utf-8")
    from summarize_baseline import summarize
    summarize(run)
archive = Path(args.archive).resolve() / args.name
if archive != run:
    shutil.copytree(run, archive, dirs_exist_ok=True)
print(args.name, "EXIT", process.returncode, "source changes", changed, flush=True)
raise SystemExit(process.returncode)
