"""Validate identities and scope of isolated original shader repetition."""
import argparse,hashlib,json
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--evidence',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    data=json.loads(args.evidence.read_text());checks=[]
    def check(name,value):checks.append({'name':name,'pass':bool(value)})
    old_index=ROOT/'test_output/shape_brushes/20261014_121806_continuation_84a9544b/artifact_index.json'
    source_index={Path(r['path']).resolve():r for r in json.loads(old_index.read_text(encoding='utf-8-sig'))}
    for name,entry in data['inputs'].items():
        path=ROOT/entry['path'].removeprefix('res://');payload=path.read_bytes();source=source_index[path.resolve()]
        check(name+'_source_bound',len(payload)==source['bytes']==entry['bytes'] and hashlib.sha256(payload).hexdigest()==source['sha256']==entry['sha256'])
    input_ids={entry['rid'] for entry in data['inputs'].values()}
    check('all_input_rids_distinct',len(input_ids)==len(data['inputs']))
    for stage,program in data['programs'].items():
        path=ROOT/program['shader_source'].removeprefix('res://')
        check(stage+'_source_current',hashlib.sha256(path.read_bytes()).hexdigest()==program['source_sha256'])
        readonly=8 if stage=='sediment' else 5
        outputs=[]
        for branch,bindings in enumerate(program['binding_maps']):
            check(stage+'_'+str(branch)+'_no_input_output_alias',len(set(bindings))==len(bindings) and set(bindings[:readonly]).issubset(input_ids) and not set(bindings[readonly:])&input_ids)
            outputs.append(set(bindings[readonly:]))
        check(stage+'_branch_outputs_distinct',not outputs[0]&outputs[1])
        records=[r for r in data['records'] if r['stage']==stage]
        check(stage+'_full_iterations',len(records)==24 and [r['iteration'] for r in records]==list(range(24)))
        fields=['sand','sediment'] if stage=='sediment' else ['wetness','compaction']
        for field in fields:
            path=args.evidence.parent/(stage+'_0_'+field+'.bin');payload=path.read_bytes();sha=hashlib.sha256(payload).hexdigest()
            check(stage+'_'+field+'_all_outputs_identical',all(r['outputs'][stage+'_'+str(branch)+'_'+field]['sha256']==sha and r['outputs'][stage+'_'+str(branch)+'_'+field]['bytes']==len(payload) for r in records for branch in range(2)))
            value=np.frombuffer(payload,dtype='<f4' if stage=='sediment' else '<f2')
            check(stage+'_'+field+'_legal',len(value)==65536 and np.isfinite(value).all() and (value>=0).all() and (stage=='sediment' or (value<=1).all()))
    result={'pass':all(c['pass'] for c in checks),'checks':checks,'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'scope':'Only fixed completed-tick238 input fixture, delta1/90 and isolated imported shaders; first divergent live operator is not reconstructed and G4/G8 remain unproven'}
    (args.output/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print('FIXED_STAGE_REFERENCE',result['pass'],len(checks));raise SystemExit(0 if result['pass'] else 1)

if __name__=='__main__':main()
