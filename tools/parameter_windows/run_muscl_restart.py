"""Run cold restart against an isolated source snapshot, avoiding workspace drift."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source-result", type=Path, default=root / "task/muscl_recording_optimization/evidence/restart/seed-result.json")
parser.add_argument("--output", type=Path, default=root / "test_output/muscl_recording_cache/restart")
parser.add_argument("--engine", default="D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe")
options = parser.parse_args()
target = options.output.resolve()
target.mkdir(parents=True, exist_ok=False)
source_config = json.loads(options.source_result.read_text(encoding="utf-8"))
for folder in ("scripts", "shaders"):
    shutil.copytree(root / folder, target / folder)
extra = ["assets/unified_edit/default_catalog.tres", "tools/wave_propagation/gpu_probe.gd",
         "tools/wave_propagation/native_restart_probe.gd", "tools/wave_propagation/compare_native_restart.gd"]
for resource in list(source_config["configuration"]["sources"]) + extra:
    relative = resource.removeprefix("res://")
    destination = target / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(root / relative, destination)
# Legacy checkpoint validation has inherited script dependencies outside scripts/.
# Include their static dependency closure even when the native probe never calls it.
pending = list(extra)
visited = set()
while pending:
    relative = pending.pop()
    if relative in visited:
        continue
    visited.add(relative)
    source = root / relative
    destination = target / relative
    if not destination.exists():
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    if source.suffix == ".gd":
        dependencies = re.findall(r'(?:preload\(\s*|extends\s+)["\']res://([^"\']+)', source.read_text(encoding="utf-8"))
    elif source.suffix in (".tres", ".tscn"):
        dependencies = re.findall(r'path="res://([^"]+)"', source.read_text(encoding="utf-8"))
    else:
        dependencies = []
    pending.extend(dependencies)
cache = root / ".godot/global_script_class_cache.cfg"
if cache.exists():
    (target / ".godot").mkdir(exist_ok=True)
    shutil.copy2(cache, target / ".godot/global_script_class_cache.cfg")
(target / "project.godot").write_text('config_version=5\n[application]\nconfig/name="muscl-cache-verification"\n[rendering]\nrendering_device/driver.windows="d3d12"\n', encoding="utf-8")
engine = options.engine
for mode in ("seed", "resume"):
    (target / mode).mkdir(exist_ok=True)
    args = [engine, "--path", str(target), "--script", "res://tools/wave_propagation/native_restart_probe.gd",
            "--", "--mode=" + mode, "--output=res://" + mode + "/data"]
    if mode == "resume":
        args.append("--input=res://seed/data/seed.sandue")
    with (target / mode / "run.log").open("w", encoding="utf-8") as log:
        subprocess.run(args, stdout=log, stderr=subprocess.STDOUT, timeout=180, check=True)
    assert "ERROR:" not in (target / mode / "run.log").read_text(encoding="utf-8"), target / mode / "run.log"
    result = json.loads((target / mode / "data/result.json").read_text(encoding="utf-8"))
    assert result["outcome"] == "pass", result
    print(mode, "PASS", flush=True)
with (target / "comparison.log").open("w", encoding="utf-8") as log:
    subprocess.run([engine, "--headless", "--path", str(target), "--script",
                    "res://tools/wave_propagation/compare_native_restart.gd", "--", "res://"],
                   stdout=log, stderr=subprocess.STDOUT, timeout=60, check=True)
assert "ERROR:" not in (target / "comparison.log").read_text(encoding="utf-8"), target / "comparison.log"
result = json.loads((target / "comparison.json").read_text(encoding="utf-8"))
assert result["outcome"] == "pass", result
pins = {str(p.relative_to(target)).replace("\\", "/"): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in target.rglob("*") if p.is_file() and p.suffix in (".gd", ".glsl", ".glslinc", ".tres", ".gdshader")}
(target / "source_hashes.json").write_text(json.dumps(pins, indent=2), encoding="utf-8")
print("COLD_RESTART_EXACT PASS", flush=True)
