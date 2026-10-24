import argparse
import json
import subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser()
parser.add_argument('--run-id',default='static_v1')
parser.add_argument('--texture',default='res://assets/water_foam/foam_cells.png')
parser.add_argument('--shader',default='res://assets/water_foam/static_candidate.gdshader')
parser.add_argument('--gate',default='G1',choices=['G0','G1','G2','G3','G4'])
parser.add_argument('--foam-baseline',action='store_true')
parser.add_argument('--scene',choices=['main','test1_geometry'])
parser.add_argument('--quick-flow',action='store_true')
parser.add_argument('--standalone-flow',action='store_true')
parser.add_argument('--hide-brush-overlays',action='store_true')
parser.add_argument('--layer-only',action='store_true')
parser.add_argument('--contact-gain',type=float)
parser.add_argument('--ignore-parameter-config',action='store_true')
parser.add_argument('--isolated-foam-config',action='store_true')
parser.add_argument('--probe',default='foam_static_candidate_probe.gd',choices=['foam_static_candidate_probe.gd','foam_strength_probe.gd','foam_scale_probe.gd','foam_appearance_probe.gd','foam_flow_probe.gd','foam_natural_sequence.gd','foam_original_gain_probe.gd','foam_shore_layers_probe.gd','foam_shore_gain_probe.gd','foam_edit_probe.gd','foam_formal_probe.gd','foam_lifecycle_probe.gd'])
parser._option_string_actions['--probe'].choices.append('foam_authority_switch_probe.gd')
parser._option_string_actions['--probe'].choices.append('foam_authority_boundary_probe.gd')
args=parser.parse_args()
OUT=ROOT/'task/water_foam_visual/验收'/args.gate/args.run_id
if OUT.exists():raise SystemExit('Output already exists; preserve the previous run')
parameter_config=None
if args.isolated_foam_config:
    OUT.mkdir(parents=True)
    parameter_config=OUT/'startup.json'
    values=dict(visual_foam_detail_scale_per_m=1.4,visual_foam_hole_strength=0.65,visual_foam_flow_cycle_s=3.0)
    parameter_config.write_text(json.dumps({'version':1,'scenes':{key:values for key in ['main','test1_geometry']}},indent=2),encoding='utf-8')
for scene in [args.scene] if args.scene else ['main','test1_geometry']:
    dest=OUT/scene
    dest.mkdir(parents=True)
    (OUT/'.gdignore').touch()
    cmd=['D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe','--path',str(ROOT),'--script','res://tests/visual_water_alignment/'+args.probe,'--','--scene='+scene,'--output=res://'+dest.relative_to(ROOT).as_posix()]
    cmd.append('--foam-texture='+args.texture)
    cmd.append('--foam-shader='+args.shader)
    if args.quick_flow:cmd.append('--quick-flow')
    if args.foam_baseline:cmd.append('--foam-baseline')
    if args.standalone_flow:cmd.append('--standalone-flow')
    if args.hide_brush_overlays:cmd.append('--hide-brush-overlays')
    if args.layer_only:cmd.append('--layer-only')
    if args.contact_gain is not None:cmd.append('--contact-gain='+str(args.contact_gain))
    if args.ignore_parameter_config:cmd.append('--ignore-parameter-config')
    if parameter_config:cmd.append('--parameter-config='+parameter_config.as_posix())
    (dest/'command.json').write_text(json.dumps(cmd,ensure_ascii=False,indent=2),encoding='utf-8')
    with (dest/'stdout.log').open('wb') as out,(dest/'stderr.log').open('wb') as err:
        try:
            p=subprocess.run(cmd,cwd=ROOT,stdout=out,stderr=err,timeout=600)
            result=dict(exit_code=p.returncode,timeout=False)
        except subprocess.TimeoutExpired:result=dict(exit_code=None,timeout=True)
    (dest/'result.json').write_text(json.dumps(result),encoding='utf-8')
    print(scene,result,flush=True)
    if result['exit_code']!=0:break
