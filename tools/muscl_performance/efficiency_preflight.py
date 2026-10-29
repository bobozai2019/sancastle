"""Record this round's immutable baseline inventory and space allowance."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'task/muscl_gpu_efficiency/验收/t00_preflight_v1'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    OUT.mkdir(parents=True, exist_ok=False)
    files = [ROOT/'project.godot', ROOT/'icon.svg']
    for folder in ('scripts','shaders','scenes','assets','addons','tools'):
        files += [p for p in (ROOT/folder).rglob('*') if p.is_file()]
    files += [p for p in (ROOT/'tests').rglob('*') if p.is_file() and
              (p.suffix in ('.gd','.glsl','.glslinc','.gdshader','.tres','.tscn','.uid','.json','.import') or
               'visual_water_alignment/prototypes/' in p.as_posix())]
    files = sorted(set(files))
    inventory = {p.relative_to(ROOT).as_posix(): {'bytes':p.stat().st_size,'sha256':digest(p)} for p in files}
    imports = set()
    for p in files:
        if p.suffix == '.import':
            imports.update(re.findall(r'"res://([^"\n]+)"',p.read_text(encoding='utf-8')))
    imported = {}
    for relative in sorted(imports):
        if relative.startswith('.godot/imported/'):
            p=ROOT/relative
            imported[relative]={'bytes':p.stat().st_size,'sha256':digest(p)} if p.is_file() else None
    source_bytes=sum(v['bytes'] for v in inventory.values())
    import_bytes=sum(v['bytes'] for v in imported.values() if v)
    # Worst case zip no compression; reference includes only a subset of sources.
    budget={'source_bytes':source_bytes,'referenced_import_bytes':import_bytes,
            'archive_and_reference_bytes':2*source_bytes,
            'two_project_bytes':2*(source_bytes+import_bytes),
            'extra_shader_cache_bytes':2*1024**3,'evidence_allowance_bytes':4*1024**3,
            'required_reserve_bytes':5*1024**3}
    budget['required_free_bytes']=sum(budget[k] for k in ('archive_and_reference_bytes','two_project_bytes','extra_shader_cache_bytes','evidence_allowance_bytes','required_reserve_bytes'))
    budget['actual_free_bytes']=shutil.disk_usage(ROOT).free
    budget['fits']=budget['actual_free_bytes']>=budget['required_free_bytes']
    engine=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe')
    data={'root':str(ROOT),'files':inventory,'imported':imported,'budget':budget,
          'python':sys.version,'python_path':sys.executable,
          'engine':{'path':str(engine),'bytes':engine.stat().st_size,'sha256':digest(engine),
                    'version':subprocess.check_output([str(engine),'--version'],text=True).strip()},
          'git_head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
          'git_status':subprocess.check_output(['git','status','--porcelain=v1','-z'],cwd=ROOT).decode('utf-8'),
          'parameter_source':str(Path(os.environ['APPDATA'])/'Godot/app_userdata/sandcastle/parameters')}
    (OUT/'inventory.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'files':len(files),'imports':len(imported),'missing_imports':[p for p,v in imported.items() if v is None],'budget':budget},indent=2))
    if not budget['fits']:raise SystemExit('Insufficient free space')

if __name__=='__main__':main()
