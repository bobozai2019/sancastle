"""One visible functional probe, immutable identity and explicit process exit."""
import argparse, hashlib, json, shutil, subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--project',required=True);p.add_argument('--archive',required=True);p.add_argument('--name',required=True);p.add_argument('--script',required=True);p.add_argument('--output-file',default='result.json');p.add_argument('extra',nargs='*');a=p.parse_args()
project=Path(a.project);folder=project/'test_output/physics_threading'/a.name
folder.mkdir(parents=True,exist_ok=True)
if (folder/'exit.json').exists():raise SystemExit('preserve existing run')
identity={str(f.relative_to(project)):hashlib.sha256(f.read_bytes()).hexdigest() for base in ['scripts','scenes','shaders','tests/integration'] for f in (project/base).rglob('*') if f.is_file()}
binary='D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
command=[binary,'--path',str(project),'--script',a.script,'--','--output=res://test_output/physics_threading/'+a.name+'/'+a.output_file]+a.extra
(folder/'manifest.json').write_text(json.dumps({'command':command,'sources':identity,'binary_sha256':hashlib.sha256(Path(binary).read_bytes()).hexdigest()},indent=2))
with (folder/'runtime.log').open('w') as log:result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=180)
changes=[f for f,h in identity.items() if hashlib.sha256((project/f).read_bytes()).hexdigest()!=h]
(folder/'exit.json').write_text(json.dumps({'exit':result.returncode,'source_changes':changes},indent=2))
shutil.copytree(folder,Path(a.archive)/a.name,dirs_exist_ok=True)
print(a.name,'EXIT',result.returncode,'changed',changes,flush=True)
raise SystemExit(result.returncode or bool(changes))
