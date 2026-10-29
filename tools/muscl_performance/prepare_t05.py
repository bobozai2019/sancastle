"""Prototype only redundant material copies, preserving ownership and callbacks."""
from pathlib import Path
import difflib
import hashlib
import json
import shutil

ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'test_output/muscl_performance_round2/projects/t04_retry_v1'
TARGET=ROOT/'test_output/muscl_performance_round2/projects/t05_material_copy_v1'
EVIDENCE=ROOT/'task/muscl_performance_round2/验收/t05_prototype'
shutil.copytree(BASE,TARGET)
EVIDENCE.mkdir(parents=True,exist_ok=False)

def change(relative,before,after):
    p=TARGET/relative;text=p.read_text(encoding='utf-8')
    if text.count(before)!=1:raise RuntimeError((relative,text.count(before)))
    p.write_text(text.replace(before,after),encoding='utf-8',newline='\n')

recorder='scripts/simulation/unified_edit/water_muscl.gd'
coupled='scripts/simulation/unified_edit/coupled.gd'
normalize='shaders/simulation/muscl/rk_normalize.glsl'
change(coupled,'func muscl_recording_passes(live: int) -> Array:', '''# Immutable recording capability: after the complete accepted MUSCL record,
# commit has made sand/wetness/compaction slots equal. This says nothing about
# arbitrary wrapped/custom callbacks; they must retain full normalization.
func muscl_material_slots_synced() -> bool:
\treturn stage_transport

func muscl_recording_passes(live: int) -> Array:''')
change(recorder,'var push0:=PackedInt32Array', '''# Consume an explicit immutable provider capability, not its private fields.
\tvar material_synced: bool=not water.coupled_recorder.is_valid()
\tif _standard_coupling:
\t\tvar provider=water.coupled_recorder.get_object()
\t\tmaterial_synced=provider.has_method("muscl_material_slots_synced") and provider.muscl_material_slots_synced()
\tvar normalize_push:=PackedInt32Array([1 if material_synced else 0,0,0,0]).to_byte_array()
\tvar push0:=PackedInt32Array''')
change(recorder,'_append_pass("rk_normalize",sets.rk_normalize,PackedByteArray(),step,true)',
 '_append_pass("rk_normalize",sets.rk_normalize,normalize_push,step,true)')
change(normalize,'void main(){','layout(push_constant,std430) uniform Params {uint skip_material;uint a,b,c;}p;\nvoid main(){')
change(normalize,'imageStore(sand0,q,imageLoad(sand1,q));imageStore(wet0,q,imageLoad(wet1,q));imageStore(comp0,q,imageLoad(comp1,q));imageStore(flux0,q,imageLoad(flux1,q));',
 'if(p.skip_material==0u){imageStore(sand0,q,imageLoad(sand1,q));imageStore(wet0,q,imageLoad(wet1,q));imageStore(comp0,q,imageLoad(comp1,q));}\n imageStore(flux0,q,imageLoad(flux1,q));')
identity={};diff=[]
for r in [recorder,coupled,normalize]:
    d=EVIDENCE/'sources'/r;d.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(TARGET/r,d)
    identity[r]=hashlib.sha256((TARGET/r).read_bytes()).hexdigest()
    diff.extend(difflib.unified_diff((BASE/r).read_text(encoding='utf-8').splitlines(True),(TARGET/r).read_text(encoding='utf-8').splitlines(True),fromfile='a/'+r,tofile='b/'+r))
(EVIDENCE/'candidate.diff').write_text(''.join(diff),encoding='utf-8')
(EVIDENCE/'identity.json').write_text(json.dumps({'base':str(BASE),'candidate':str(TARGET),'source_hashes':identity,
 'scope':'Water normalize skips only material copies declared redundant; no changes to Coupled commit or public slots; custom callbacks retain full copy','new_gpu_allocations':0},indent=2),encoding='utf-8')
print(TARGET)
