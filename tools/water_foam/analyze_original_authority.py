"""Exact original-shader numerical replay audit; raw bytes, no tolerance."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.unified_edit_pipeline.native_variant import VariantReader

def load(path):return VariantReader(path.read_bytes()[48:]).document()

def compare(a,b):
    fields={}
    for key,x in a['native']['fields'].items():
        y=b['native']['fields'][key]
        dtype='<f2' if key in ['wetness','compaction'] else ('u1' if key=='obstacle' else '<f4')
        ax,by=np.frombuffer(x,dtype=dtype),np.frombuffer(y,dtype=dtype)
        fields[key]={'bytes_equal':x==y,'different_components':int(np.count_nonzero(ax!=by)),'max_abs':float(np.abs(ax.astype(np.float64)-by.astype(np.float64)).max())}
    keys=['configuration','simulation','selection','wave_requests','wave_start_times','cohesion_yield_height_m','sim_tick','advanced_time_s']
    return {'fields':fields,'physical_fields_exact':all(v['bytes_equal'] for v in fields.values()),'native_groups_exact':{k:x==b['native'][k] for k,x in a['native'].items()},'metadata_exact':{k:a[k]==b[k] for k in keys if k in a and k in b}}

parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--run-id',required=True);args=parser.parse_args()
folder=ROOT/'task/water_foam_visual/验收/G4'/args.run_id/'main'
receipt=json.loads((folder/'result.json').read_text('utf-8'))
assert not receipt['timeout'] and not receipt['source_drift']
probe=json.loads((folder/'probe.json').read_text('utf-8'))
assert all(x['pass'] for x in probe['checks'] if 'identity' in x['name'])
cases=[load(folder/f'case{i}_final.sandue') for i in range(3)]
report={'scope':'Original pre-integration water and side shader bytes/contact1 for cases0/1; formal shaders/contact0.55 for case2. Current physical sources and initial checkpoint identical. Not a whole-project historical replay. No tolerance or performance conclusion.','process':receipt,'probe_pass':probe['pass'],'checks':len(probe['checks']),'failed_checks':[x['name'] for x in probe['checks'] if not x['pass']],'variants':probe['observations']['variants'],'AA':compare(cases[0],cases[1]),'AB':compare(cases[1],cases[2]),'analysis_tool_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
(folder.parent/'analysis.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'checks':report['checks'],'failed_checks':report['failed_checks'],'AA':report['AA']['physical_fields_exact'],'AB':report['AB']['physical_fields_exact'],'max_abs':{p:{k:v['max_abs'] for k,v in report[p]['fields'].items() if not v['bytes_equal']} for p in ['AA','AB']}},ensure_ascii=False,indent=2))
