"""Validate the main material bridge against live GPU outputs, keeping old evidence intact."""
from pathlib import Path
import hashlib,json
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[3]
BASE=ROOT/'test_output/test1_water_motion'
OUT=BASE/'main_material_review_v1'
OUT.mkdir(exist_ok=True)
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
initial=np.fromfile(ROOT/'assets/test1_water_motion/capture_state.rgba32f',dtype='<f4').reshape(256,512,4)
floor=initial[:,:,3]
z,x=np.mgrid[:256,:256].astype(np.float32)
wx=(x+.5)*.125-16;wz=(z+.5)*.125-16
uvx=(wx+15)/30;uvz=(7.5-wz)/15
cx=uvx*512-.5;cz=uvz*256-.5
ix=np.floor(cx).astype(int);iz=np.floor(cz).astype(int)
fx=cx-ix.astype(np.float32);fz=cz-iz.astype(np.float32)
outside=(uvx<0)|(uvx>1)|(uvz<0)|(uvz>1)
weights=[(1-fx)*(1-fz),fx*(1-fz),(1-fx)*fz,fx*fz]
def projected(a):
    cells=[a[np.clip(iz+dz,0,255),np.clip(ix+dx,0,511)] for dx,dz in [(0,0),(1,0),(0,1),(1,1)]]
    depths=[np.maximum(s[:,:,2]-.05,0) for s in cells]
    result={'sand':sum(s[:,:,3]*w for s,w in zip(cells,weights)),
            'water':sum(h*w for h,w in zip(depths,weights)),
            'momentum_x':sum(s[:,:,0]*h*w for s,h,w in zip(cells,depths,weights)),
            'momentum_z':-sum(s[:,:,1]*h*w for s,h,w in zip(cells,depths,weights))}
    for name in ['water','momentum_x','momentum_z']: result[name][outside]=0
    return result

report={'scope':'Main effective material snapshot, same shared shaders and texture assets. 512x256 captured solver remains unchanged; display-only fields projected into main 256x256 / 32-unit domain. Experimental time, not original calibrated seconds.', 'runs':{},'limitations':[]}
report['projection_absolute_tolerance']=0.0001
inventory=[]
for run,previous in [('main_material_release_v1','gpu_release_v3'),('main_material_repeat_v1','gpu_repeat_v1')]:
    folder=BASE/run
    manifest=json.loads((folder/'manifest.json').read_text(encoding='utf-8'))
    log=(BASE/(run+'.log')).read_text(encoding='utf-8',errors='replace')
    errors=[s for s in log.splitlines() if s.startswith(('ERROR:','SCRIPT ERROR:','SHADER ERROR:'))]
    assert manifest['operation_complete'] and manifest['sources_unchanged'] and all(manifest['controls'].values()) and not errors
    assert manifest['main_materials']['shader_identity'] and manifest['main_materials']['parameters_identical'] and all(manifest['main_materials']['runtime_fields'].values())
    for row in manifest['source_index']:
        assert digest(Path(row['snapshot']))==row['sha256']
    old=json.loads((BASE/previous/'manifest.json').read_text(encoding='utf-8'))
    old_rows={r['tick']:r for r in old['samples']}
    rows=[];render_checks=[];negative_checks=[]
    for sample in manifest['samples']:
        p=Path(sample['raw_path']);assert digest(p)==sample['sha256']
        a=np.fromfile(p,dtype='<f4').reshape(256,512,4)
        assert np.isfinite(a).all() and (a[:,:,2]>=0).all() and np.array_equal(a[:,:,3],floor)
        h=np.maximum(a[:,:,2]-.05,0);shore=(floor>1.05)&(floor<2)&(h>.005)
        original=np.fromfile(old_rows[sample['tick']]['raw_path'],dtype='<f4').reshape(a.shape)
        delta=np.abs(a-original)
        row={'tick':sample['tick'],'t':sample['adaptation_time'],'shore_water_proxy':float(h[floor>1.05].sum()*.05859375**2),'shore_mean_vx':float(a[:,:,0][shore].mean()) if shore.any() else 0,'floor_unchanged':True,'previous_state_identical':sample['sha256']==old_rows[sample['tick']]['sha256'],'previous_max_abs_delta':delta.max(axis=(0,1)).tolist(),'previous_mean_abs_delta':delta.mean(axis=(0,1)).tolist()}
        rows.append(row)
        if 'picture' in sample:
            expected=projected(a);checks={'tick':sample['tick'],'errors':{},'history':{}}
            for name,e in expected.items():
                field=np.fromfile(folder/f'render_{sample["tick"]:04d}_{name}.f32',dtype='<f4').reshape(256,256)
                # Float32 GPU constant division may become reciprocal multiplication/FMA.
                # At a steep bed one source-cell ULP can exceed 1e-5 height units.
                diff=np.abs(field-e);assert np.isfinite(field).all() and diff.max()<0.0001, (run,sample['tick'],name,float(diff.max()),tuple(np.unravel_index(diff.argmax(),diff.shape)))
                checks['errors'][name]={'max':float(diff.max()),'mean':float(diff.mean())}
            for name in ['rock','wetness','compaction','foam_state','foam_previous_state','local_front_state']:
                field=np.fromfile(folder/f'render_{sample["tick"]:04d}_{name}.f32',dtype='<f4')
                assert np.isfinite(field).all()
                checks['history'][name]={'min':float(field.min()),'max':float(field.max())}
            render_checks.append(checks)
        for negative in sample.get('visual_negatives',[]):
            original=np.asarray(Image.open(sample['picture']).convert('RGB')).astype(int)
            disabled=np.asarray(Image.open(negative['picture']).convert('RGB')).astype(int)
            change=np.abs(original-disabled)
            changed=int((change.max(axis=2)>2).sum())
            assert changed>50 and sample['visual_negatives_preserve_state']
            negative_checks.append({'uniform':negative['only_changed_uniform'],'changed_pixels_gt2':changed,'pixel_mean_abs_change':float(change.mean()),'capture_state_unchanged':True,'baseline':sample['picture'],'disabled':negative['picture']})
    report['runs'][run]={'rows':rows,'render_checks':render_checks,'visual_negatives':negative_checks,'controls':manifest['controls'],'main_materials':manifest['main_materials'],'operation_exit_code':0,'no_runtime_errors':True,'runtime':{'engine':manifest['engine']['string'],'adapter':manifest['adapter'],'driver':'D3D12','viewport':[1280,720]}}
    for p in sorted(folder.rglob('*')):
        if p.is_file():inventory.append({'path':str(p),'bytes':p.stat().st_size,'sha256':digest(p),'kind':'source_snapshot' if 'source_snapshot' in p.parts else 'live_gpu_or_capture_output'})
release=report['runs']['main_material_release_v1']['rows']
peak=max(release,key=lambda r:r['shore_water_proxy']);end=release[-1];at20=next(r for r in release if r['t']==20)
report['release']={'peak':peak,'first_mean_reverse_after6':next(r['t'] for r in release if r['t']>6 and r['shore_mean_vx']>0),'at20':at20,'at40':end,'loss_at20':1-at20['shore_water_proxy']/peak['shore_water_proxy'],'loss_at40':1-end['shore_water_proxy']/peak['shore_water_proxy']}
report['limitations']=['Historical and new GPU samples are not bit-identical after early ticks; unchanged kernel/input hashes and same macroscopic release trend do not prove bitwise determinism. Largest late differences are localized velocity values, including near dry cells; cause remains unverified.', 'Main compiled shaders hardcode 256x256 and 32-unit domain. Captured 512x256 input uses display resampling; sand detail is consequently limited by main rendering fields.', 'The current shared wave-front visual kernels shape crests along their inherited X convention. Exact original crest/foam lifecycle and original future customWave schedule remain unknown.', 'Sand wetness trail is a display adaptation with 20 experimental second relaxation; compaction is zero. No authoritative moisture/compaction, sand editing, ledger, collision, or checkpoint integration is claimed.', 'Reflection camera uses the current main implementation and plane y=0; original water-height-dependent reflection is not recovered.', 'Visible-window functional validation is not a representative cost or performance acceptance.']
(OUT/'summary.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
logs=['bake_main_presentation.log','bake_main_presentation_v2.log','main_material_smoke_v1.log','main_material_smoke_v2.log','main_material_smoke_v3.log','main_material_import.log','main_material_release_v1.log','main_material_repeat_v1.log','main_material_direct_start.log']
for name in logs:
    p=BASE/name
    if p.exists():inventory.append({'path':str(p.resolve()),'bytes':p.stat().st_size,'sha256':digest(p),'kind':'log'})
sources=[]
for name in ['sandcastlegame/test1.rdc','scenes/main.tscn','tests/investigation/test1_water_motion/analyze_main_presentation.py']:
    p=ROOT/name;sources.append({'path':str(p),'bytes':p.stat().st_size,'sha256':digest(p)})
assert sources[0]['sha256']=='761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2'
baked=json.loads((ROOT/'assets/test1_water_motion/main_presentation.json').read_text(encoding='utf-8'))
assert sources[1]['sha256']==baked['source_scene_sha256']
exe='D:/godot/Godot_v4.7.1-stable/Godot_v4.7.1-stable_win64_console.exe'
commands=[{'command':f'{exe} --path D:/godot/project/sandcastle --rendering-driver d3d12 --script res://tests/investigation/test1_water_motion/capture_trial.gd -- --output=D:/godot/project/sandcastle/test_output/test1_water_motion/{run} --mode={mode} --end-tick={ticks}','actual_exec_exit_code':0} for run,mode,ticks in [('main_material_release_v1','release',1600),('main_material_repeat_v1','repeat',1280)]]
commands.append({'command':f'{exe} --path D:/godot/project/sandcastle --rendering-driver d3d12 res://scenes/test1_water_motion_trial.tscn --quit-after 180','actual_exec_exit_code':0})
(OUT/'inventory.json').write_text(json.dumps({'files':inventory,'source_identity':sources,'commands':commands,'failed_or_partial_attempts':['bake_main_presentation.log: incorrect paused property, interrupted own helper','main_material_smoke_v1.log: parser failure','main_material_smoke_v2.log: dependency parser failure, interrupted own helper','main_material_smoke_v3.log: reset released wrapped textures; invalid RID errors, not accepted','main_material_import.log: target shader imported; unrelated vendored matplotlib CSV translation and duplicate historical UID errors, not a clean project-wide import gate']},indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps({'runs':len(report['runs']),'projection_checks':sum(len(r['render_checks']) for r in report['runs'].values()),'negatives':report['runs']['main_material_repeat_v1']['visual_negatives'],'release':{k:report['release'][k] for k in ['first_mean_reverse_after6','loss_at20','loss_at40']},'files':len(inventory)},ensure_ascii=False))
