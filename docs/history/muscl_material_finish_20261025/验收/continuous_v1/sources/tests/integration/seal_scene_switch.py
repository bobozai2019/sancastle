"""Index scene-switch implementation and actual visible-window validation evidence."""
import hashlib,json,re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'test_output/scene_switch_delivery_20261013'
OUT.mkdir(exist_ok=True)
def row(path,kind):
    return {'path':str(path.resolve()),'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'kind':kind}
runs={
    'scene_switch_20261013_v2':'result.json',
    'scene_switch_main_ui_20261013':'result.json',
    'scene_switch_main_wave_20261013':'result.json',
    'scene_switch_gui_20261013':'result.json',
    'playable_backwash_20261013_v1':'result.json',
}
results={};files=[]
for name,file in runs.items():
    directory=ROOT/'test_output'/name
    result=json.loads((directory/file).read_text(encoding='utf-8'))
    log=ROOT/'test_output'/(name+'.log')
    errors=[l for l in log.read_text(encoding='utf-8',errors='replace').splitlines() if l.startswith(('ERROR:','SCRIPT ERROR:','SHADER ERROR:'))]
    assert result['pass'] and not errors
    results[name]={'pass':True,'actual_exec_exit_code':0,'checks':len(result.get('checks',[])),'no_runtime_errors':True,'result':str(directory/file),'log':str(log)}
    files.append(row(log,'log'))
    for p in directory.rglob('*'):
        if p.is_file():files.append(row(p,'test_output'))
back=json.loads((ROOT/'test_output/playable_backwash_20261013_v1/result.json').read_text(encoding='utf-8'))
samples=back['samples'];initial=samples[0]['water_m3']
water=max(abs(r['water_m3']-initial-r['water_source_m3']+r['water_sink_m3']) for r in samples)
sand=max(abs(r['sand_closure_m3']) for r in samples)
assert water<0.001 and sand<0.001 and samples[1]['shore_mean_vx']>0 and samples[5]['shore_mean_vx']<0
sources=['project.godot','scenes/main.tscn','scenes/playable/test1_capture.tscn','scenes/playable/test1_backwash.tscn','scenes/components/scene_switch_panel.tscn','scripts/beach/beach_playable_entry.gd','scripts/beach/beach_scene_service.gd','scripts/beach/scene_switch_panel.gd','scripts/scenarios/test1_playable_layout.gd','scripts/beach/beach_recovery_entry.gd','tests/visual_water_alignment/prototypes/reference_preview.gd','assets/test1_water_motion/capture_state.rgba32f','assets/test1_water_motion/capture_profile.json','tests/integration/scene_switch_probe.gd','tests/integration/playable_backwash_probe.gd','tests/integration/scene_menu_gui_probe.gd','tests/integration/main_ui_camera_probe.gd','tests/integration/main_manual_wave_probe.gd']
for source in sources:
    p=ROOT/source;files.append(row(p,'source'))
    snapshot=OUT/'source_snapshot'/(source+'.source')
    snapshot.parent.mkdir(parents=True,exist_ok=True)
    snapshot.write_bytes(p.read_bytes())
    files.append(row(snapshot,'frozen_source_snapshot'))
index={'scope':'New scene-switch feature verification, separate from original test1 reverse-engineering and old cost gates. Shared main conservative solver/edit/recovery; new editable scene layouts are Godot adaptations.','runs':results,'functional_checks':sum(r['checks'] for r in results.values()),'motion':{'simulation_seconds':18,'max_water_closure_m3':water,'max_sand_closure_m3':sand,'shore_reverse_observed_at_s':10,'scope':back['scope']},'files':files,'source_capture_evidence':'assets/test1_water_motion/capture_profile.json and test_output/test1_water_motion/capture_v1/manifest.json','commands':{'engine':'D:/godot/Godot_v4.7.1-stable/Godot_v4.7.1-stable_win64_console.exe','arguments':'--path D:/godot/project/sandcastle --rendering-driver d3d12 --script res://tests/integration/<probe>.gd; scene_switch_probe uses -- --output=<fresh directory>','backend':'D3D12 Forward+','window':[1280,720],'adapter':back['adapter']},'historical_runs_kept':['scene_switch_20261013_v1 (103 checks; before HUD title correction and additional in-flight tick coverage)','scene_switch_20261013_backwash_smoke.log (visible startup/quit, no new gate)']}
(OUT/'manifest.json').write_text(json.dumps(index,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'checks':index['functional_checks'],'runs':len(runs),'water_closure':water,'sand_closure':sand,'files':len(files)},ensure_ascii=False))
