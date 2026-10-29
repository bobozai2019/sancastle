"""Version-2 independent native supplementary envelopes; no candidate data or added tolerance."""
import argparse
import datetime
import hashlib
import itertools
import json
import shutil
from pathlib import Path
import numpy as np
from evidence_contract import identity
from reference_budget import codes,metrics,seal,QUANTA


def write(path,data):path.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--selection',required=True,type=Path);p.add_argument('--output',required=True,type=Path)
    args=p.parse_args();out=args.output
    if not out.is_absolute() or not str(out).isascii():raise ValueError('Absolute ASCII output required')
    out.mkdir(parents=True,exist_ok=False)
    for name in ['sources','raw','derived','logs']:(out/name).mkdir()
    selection=json.loads(args.selection.read_text());groups={};source_checks=[]
    for src in selection['sources']:
        expected=src['manifest'];actual=identity(expected['path'])
        if actual['sha256']!=expected['sha256'] or actual['size_bytes']!=expected['size_bytes']:raise ValueError('SOURCE_MANIFEST_CHANGED')
        manifest=json.loads(Path(expected['path']).read_text())
        if manifest['operation_status']!='complete' or manifest['errors']:raise ValueError('REFERENCE_SOURCE_INCOMPLETE')
        source_checks.append(actual)
        for ref in manifest.get('references',manifest.get('results',[])):
            req=ref['request']
            srvs=[s.get('artifact',s) for s in req['srvs']]
            key=dict(program=req['program']['sha256'],input=req['input']['sha256'],constants=req['constants']['sha256'],srvs=[s['sha256'] for s in srvs])
            digest=hashlib.sha256(json.dumps(key,sort_keys=True).encode()).hexdigest()
            group=groups.setdefault(digest,dict(reference_id='e%d_'%req['event_id']+digest[:20],event_id=req['event_id'],identity=key,
                provenance=[],outputs=[],original_program=req['program'],input=req['input'],constants=req['constants'],srvs=srvs))
            group['provenance'].append(dict(manifest=actual,local_reference_id=ref['reference_id'],role=src['role']))
            for c in ref['checks']:
                output=c.get('output',c.get('after'))
                observed=identity(output['path'])
                if observed['sha256']!=output['sha256'] or observed['size_bytes']!=2097152:raise ValueError('REFERENCE_OUTPUT_CHANGED')
                if not c['fence_complete']:raise ValueError('GPU_COMPLETION_UNPROVEN')
                group['outputs'].append(observed)
    references=[]
    for index,g in enumerate(groups.values()):
        if len(g['outputs'])<3:raise ValueError('TOO_FEW_REFERENCE_SAMPLES')
        print(json.dumps(dict(phase='freeze_reference',index=index,reference_id=g['reference_id'],samples=len(g['outputs']))),flush=True)
        unique_outputs=list({a['sha256']:a for a in reversed(g['outputs'])}.values())
        decoded=[codes(a['path']) for a in unique_outputs];arrays={};rules={}
        for field in decoded[0]:
            values=np.stack([d[field] for d in decoded]);arrays[field+'_min']=values.min(axis=0);arrays[field+'_max']=values.max(axis=0)
            observed={key:0. for key in ['mae','p99','max']}
            for left,right in itertools.combinations(range(len(values)),2):
                m=metrics(values[left],values[right])
                for key in observed:observed[key]=max(observed[key],m[key])
            quantum=QUANTA.get(field,QUANTA['A'] if field=='h' else 1)
            rules[field]=dict(field=field,metric=['mae','p99','max','pointwise interval'],reference_noise_code_units=observed,
                reference_noise={key:value*quantum for key,value in observed.items()},quantization_step=quantum,
                quantization_bound=0,floating_point_budget=0,limit_code_units=observed,
                limit={key:value*quantum for key,value in observed.items()},
                branch_rule='Per-coordinate observed code set' if field in ['B','source','sea','wet'] else 'Per-coordinate sampled interval AND all aggregate limits',
                derivation='Both inputs to comparison are packed original-format outputs. No additional quantization/FP error allowance is independently justified. Exact codes outside sampled original in-place variation fail; this is a bounded empirical acceptance rule, not a universal error theorem.',
                evidence_refs=[a['sha256'] for a in g['outputs']])
            if field in ['B','source','sea','wet']:arrays[field+'_samples']=values.astype(np.uint8)
        bands=out/'raw'/(g['reference_id']+'.npz');np.savez_compressed(bands,**arrays)
        references.append(dict(g,baseline=g['outputs'][0],bands=identity(bands),fields=rules,reference_sample_count=len(g['outputs']),distinct_output_count=len(unique_outputs)))
        write(out/'logs/progress.json',dict(completed=index+1,total=len(groups)))
    budget=seal(dict(schema_version='1.0',frozen_at=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
        role='empirical original-program encoded-output acceptance budget',candidate_evaluated=False,budget_revision=2,
        supersedes=selection['supersedes'],independent_counterexample=selection['independent_counterexample'],
        revision_reason=selection['revision_reason'],deduplication='Byte-identical original outputs decoded once; min/max, categorical membership and maximum all-pair aggregate errors are unchanged by duplicate removal. All repeat identities and counts retained.',
        input_selection=identity(args.selection),sources=source_checks,references=references,
        scope='Only exact program/input/constant/dependency identities listed. Other states, hardware, clock sequences or ping-pong adaptations are not evaluated by these numbers.',
        rules=['Use per-cell sampled ranges plus MAE/P99/max, never one global maximum alone',
               'B/source/sea/wet require observed categorical membership per cell',
               'Zero extra FP/quantization allowance: no source experiment justifies relaxing encoded outputs',
               'Sampled ranges are not universal scheduling bounds. An unseen legitimate original execution can fail and needs independent new original evidence plus a versioned revision.',
               'A Godot failure cannot by itself justify increasing limits. Preserve old failures and freeze new scope before re-comparison.',
               'h uses amount-code units above exact .05 threshold; physical metrics multiply by the A quantum',
               'Integer roundtrip and exact buffer extent are required before field comparison']))
    write(out/'error_budget.json',budget)
    for name in ['freeze_reference_budget_v2.py','reference_budget.py','evidence_contract.py']:
        shutil.copyfile(Path(__file__).with_name(name),out/'sources'/name)
    write(out/'manifest.json',dict(schema_version='1.0',run_id=out.name,operation_status='complete',verification_status='not_evaluated',
        artifacts=[identity(p) for p in out.rglob('*') if p.is_file()],errors=[],scope='Budget freeze only; checker positives/negatives and G3 review are separate'))
    print(json.dumps(dict(references=len(references),budget=identity(out/'error_budget.json'))),flush=True)


if __name__=='__main__':main()
