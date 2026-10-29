"""Compare actual fault publication/cleanup outcomes across isolated variants."""
import json
from pathlib import Path
from baseline import run,ROOT,TASK

projects=ROOT/'test_output/muscl_performance_round2/projects'
engine=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe')
comparison={}
for case in ('negative','nonfinite'):
    variants={}
    for name,project in [('a','diagnostic_final'),('b','t03_shared_v1')]:
        run_id='t03_'+case+'_'+name
        run(engine,run_id,'special',projects/project,['--case='+case])
        directory=TASK/'验收'/run_id
        result=json.loads((directory/'result.json').read_text(encoding='utf-8'))
        manifest=json.loads((directory/'manifest.json').read_text(encoding='utf-8'))
        assert result['outcome']=='pass' and not manifest['source_drift'] and manifest['user_unchanged'],run_id
        variants[name]={'fault':result['fault'],'snapshots':[
            {k:v for k,v in row.items() if k!='fields'} | {'fields':{k:{'bytes':v['bytes'],'sha256':v['sha256']} for k,v in row['fields'].items()}}
            for row in result['snapshots']]}
    comparison[case]={'equal':variants['a']==variants['b'],'variants':variants}
(TASK/'验收/t03_negative_comparison.json').write_text(json.dumps(comparison,indent=2),encoding='utf-8')
assert all(r['equal'] for r in comparison.values()),'negative fixture difference'
print('T03_NEGATIVES_EXACT PASS',flush=True)
