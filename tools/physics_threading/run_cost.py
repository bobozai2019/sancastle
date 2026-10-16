import argparse
import hashlib
import json
import shutil
import subprocess
import time
from pathlib import Path
from windows_telemetry import Telemetry
from summarize_cost import summarize

p=argparse.ArgumentParser();p.add_argument("--project",required=True);p.add_argument("--archive",required=True);p.add_argument("--name",required=True)
p.add_argument("--origin",default="");p.add_argument("--policy",default="baseline");p.add_argument("--minimum",type=int,default=1);p.add_argument("--seconds",type=float,default=30)
p.add_argument("--binary",default="D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe")
a=p.parse_args();project=Path(a.project).resolve();run=project/"test_output/physics_threading"/a.name
if (run/"trace.json").exists():raise SystemExit("existing result must not be overwritten")
run.mkdir(parents=True,exist_ok=True)
command=[a.binary,"--path",str(project),"--script","res://tools/physics_threading/cost_probe.gd","--",
         "--output=res://test_output/physics_threading/"+a.name,"--detailed","--live-seconds="+str(a.seconds),
         "--collision-prepare="+a.policy,"--collision-prepare-min="+str(a.minimum)]
if a.origin:command.append("--origin="+a.origin)
identity={}
for folder in ["scripts","scenes","shaders","assets","tools/physics_threading"]:
    for file in (project/folder).rglob("*"):
        if file.is_file():identity[file.relative_to(project).as_posix()]=hashlib.sha256(file.read_bytes()).hexdigest()
identity["project.godot"]=hashlib.sha256((project/"project.godot").read_bytes()).hexdigest()
(run/"manifest.json").write_text(json.dumps({"command":command,"sources":identity,"binary_sha256":hashlib.sha256(Path(a.binary).read_bytes()).hexdigest()},indent=2),encoding="utf-8")
started=time.monotonic();timed_out=False
with (run/"runtime.log").open("w",encoding="utf-8") as log, (run/"telemetry.jsonl").open("w",encoding="utf-8") as stream:
    process=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT)
    telemetry=Telemetry(process.pid)
    (run/"live_process.json").write_text(json.dumps({"pid":process.pid,"command":command,"started_utc_ns":time.time_ns()},indent=2))
    try:
        while process.poll() is None:
            stream.write(json.dumps(telemetry.sample())+"\n");stream.flush()
            if time.monotonic()-started>a.seconds+300:
                timed_out=True;process.kill();break
            time.sleep(1)
        process.wait()
    finally:telemetry.close()
changed=[f for f,h in identity.items() if hashlib.sha256((project/f).read_bytes()).hexdigest()!=h]
(run/"exit.json").write_text(json.dumps({"exit":process.returncode,"timed_out":timed_out,"source_changes":changed,"elapsed_s":time.monotonic()-started},indent=2))
if process.returncode==0 and (run/"trace.json").exists():
    result=summarize(run)
    (run/"effective_config.json").write_text(json.dumps(result["configuration"],indent=2),encoding="utf-8")
archive=Path(a.archive).resolve()/a.name
if archive!=run:shutil.copytree(run,archive,dirs_exist_ok=True)
print(a.name,"EXIT",process.returncode,"changed",changed,flush=True)
raise SystemExit(0 if process.returncode==0 and not timed_out and not changed and (run/"summary.json").exists() else 1)
