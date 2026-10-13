import json,subprocess,time,hashlib,sys
from pathlib import Path
from process_watch import godot_processes
root=Path(__file__).resolve().parents[2];out=(root/sys.argv[1]).resolve()
initial=godot_processes()
if any(p['pid']!=21316 for p in initial):raise RuntimeError('Other Godot active')
out.mkdir(parents=True,exist_ok=False)
paths=[]
for folder in ['assets/water_material_natural_candidate','tests/water_material_natural','scenes/water_material_natural_candidate']:
 paths.extend(p for p in (root/folder).iterdir() if p.is_file() and not p.name.endswith('.uid'))
paths.extend(root/p for p in ['assets/test1_beach/test1_beach_release.json','assets/test1_beach/test1_water_front.gdshader','assets/test1_beach/test1_front_foam_splats.gdshader','assets/test1_beach/test1_bed_lit_fast.gdshader','scripts/visual/test1_beach_fixed_entry.gd','scripts/visual/water_render_staging_entry.gd','scenes/water_material_natural_candidate/rdc_v1_fixed.tscn','scenes/water_material_natural_candidate/rdc_v1_coupled.tscn'])
index=[]
for p in paths:
 q=out/'source_snapshot'/(str(p.relative_to(root))+'.source');q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(p.read_bytes());index.append({'path':str(p),'snapshot':str(q),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(out/'source_index.json').write_text(json.dumps(index,indent=2))
startup=subprocess.STARTUPINFO();startup.dwFlags=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
command=['D:/other_software/RenderDoc/qrenderdoc.exe','--python',str(root/'tests/water_material_natural/rdc_owned_host.py')]
p=subprocess.Popen(command,startupinfo=startup);context={'host_pid':p.pid,'output':str(out),'project':str(root),'godot':'D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe','checkpoint':str(root/'test_output/water_material_natural/t06_common_checkpoint_v1/common.sandcp')}
(root/'test_output/water_material_natural/rdc_active_context.json').write_text(json.dumps(context,indent=2));started=time.time();code=p.wait()
result={'host_exit_code':code,'host_pid':p.pid,'command':command,'elapsed_s':time.time()-started,'initial_godot':initial,'sources_unchanged':all(hashlib.sha256(Path(x['path']).read_bytes()).hexdigest()==x['sha256'] for x in index),'scope':'Owned capture helper operation only; not final cost acceptance.'}
(out/'host_process_result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
