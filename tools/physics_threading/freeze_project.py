"""Freeze actual dirty runtime sources outside the original Godot scan."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

p=argparse.ArgumentParser();p.add_argument("--source",required=True);p.add_argument("--destination",required=True);p.add_argument("--manifest",required=True)
a=p.parse_args();source=Path(a.source).resolve();destination=Path(a.destination).resolve()
if destination==source or source in destination.parents:raise SystemExit("snapshot must be outside source project")
if destination.exists():raise SystemExit("new snapshot destination required; preserve existing runs")
destination.mkdir(parents=True)
index=[]
for folder in ["assets","addons","scripts","scenes","shaders","tests","tools",".godot/imported"]:
    for item in (source/folder).rglob("*"):
        if not item.is_file():continue
        relative=item.relative_to(source)
        if "test_output" in relative.parts or ".git" in relative.parts:continue
        if item.suffix in [".scgpu",".log",".csv"]:continue
        if item.suffix==".png" and relative.parts[0] not in ["assets","scenes"]:continue
        target=destination/relative;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(item,target)
        index.append({"path":relative.as_posix(),"bytes":target.stat().st_size,"sha256":hashlib.sha256(target.read_bytes()).hexdigest()})
for relative in ["project.godot","icon.svg",".godot/global_script_class_cache.cfg",".godot/uid_cache.bin",".godot/scene_groups_cache.cfg"]:
    item=source/relative
    if item.exists():
        target=destination/relative;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(item,target)
        index.append({"path":relative,"bytes":target.stat().st_size,"sha256":hashlib.sha256(target.read_bytes()).hexdigest()})
changed=[row["path"] for row in index if hashlib.sha256((source/row["path"]).read_bytes()).hexdigest()!=row["sha256"]]
manifest=Path(a.manifest);manifest.parent.mkdir(parents=True,exist_ok=True)
manifest.write_text(json.dumps({"source":str(source),"destination":str(destination),"files":index,"changes_during_copy":changed},indent=2),encoding="utf-8")
print("FROZEN",len(index),"files; changes",changed)
raise SystemExit(1 if changed else 0)
