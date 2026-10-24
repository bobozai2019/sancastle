"""Exact offline comparisons for the checkpoint-capture single-factor probe."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.unified_edit_pipeline.native_variant import VariantReader

def frozen(value):
    if isinstance(value,memoryview):return bytes(value)
    if isinstance(value,dict):return {k:frozen(v) for k,v in value.items()}
    if isinstance(value,list):return [frozen(v) for v in value]
    return value

def load(path):return VariantReader(path.read_bytes()[48:]).document()

def compare(a,b):
    fields={}
    for key,raw in a['native']['fields'].items():
        other=b['native']['fields'][key]
        dtype='<f2' if key in ['wetness','compaction'] else ('u1' if key=='obstacle' else '<f4')
        x,y=np.frombuffer(raw,dtype=dtype),np.frombuffer(other,dtype=dtype)
        difference=np.abs(x.astype(np.float64)-y.astype(np.float64))
        fields[key]={'bytes_equal':bytes(raw)==bytes(other),'different_components':int(np.count_nonzero(x!=y)),'max_abs':float(difference.max())}
    groups={key:frozen(value)==frozen(b['native'][key]) for key,value in a['native'].items()}
    meta=[k for k in ['configuration','simulation','selection','wave_requests','wave_start_times','cohesion_yield_height_m','sim_tick','advanced_time_s'] if k in a and k in b]
    controls=np.frombuffer(a['native']['control'],dtype='<u4')
    other_controls=np.frombuffer(b['native']['control'],dtype='<u4')
    return {'fields':fields,'native_groups_exact':groups,'metadata_exact':{k:frozen(a[k])==frozen(b[k]) for k in meta},'control_u32_differences':[{'word':int(i),'a':int(controls[i]),'b':int(other_controls[i])} for i in np.flatnonzero(controls!=other_controls)],'physical_fields_exact':all(v['bytes_equal'] for v in fields.values())}

parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--run-id',required=True);args=parser.parse_args()
folder=ROOT/'task/water_foam_visual/验收/G4'/args.run_id/'main'
receipt=json.loads((folder/'result.json').read_text('utf-8'))
assert not receipt['timeout'] and not receipt['source_drift']
probe=json.loads((folder/'probe.json').read_text('utf-8'))
result={'scope':'Exact original bytes and float component magnitudes, no tolerance. Raw control identity differences are diagnostic and do not by themselves imply changed physics.','process':receipt,'probe_pass':probe['pass'],'checks':len(probe['checks']),'failed_checks':[x['name'] for x in probe['checks'] if not x['pass']],'analysis_tool_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'groups':{}}
for label in ['end_only','with_middle']:
    cases=[load(folder/f'{label}_case{i}_final.sandue') for i in range(3)]
    result['groups'][label]={'AA':compare(cases[0],cases[1]),'AB':compare(cases[1],cases[2])}
stages={}
for stage in ['restored','place_sand_0','place_sand_1','place_sand_30','remove_sand_0','remove_sand_1','remove_sand_30']:
    # Historical probe labels concatenate case index and tool name.
    suffix='_'+stage if stage=='restored' else stage
    cases=[load(folder/f'with_middle_case{i}{suffix}.sandue') for i in range(3)]
    stages[stage]={'AA':compare(cases[0],cases[1]),'AB':compare(cases[1],cases[2])}
result['middle_stages']=stages
(folder.parent/'analysis.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'groups':{k:{p:x['physical_fields_exact'] for p,x in v.items()} for k,v in result['groups'].items()},'stages':{k:{p:x['physical_fields_exact'] for p,x in v.items()} for k,v in stages.items()},'checks':result['checks'],'failed_checks':len(result['failed_checks'])},ensure_ascii=False,indent=2))
