"""Recover comparisons from a terminal completed snapshot GPU run without rerunning GPU."""
import argparse
import json
import shutil
from pathlib import Path
import numpy as np
from evidence_contract import identity
from reference_budget import codes,metrics


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--run',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);args=ap.parse_args()
    run=args.run.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False);(out/'comparisons').mkdir()
    request=json.loads((run/'request.json').read_text());result=json.loads((run/'raw/probe_result.json').read_text())
    def checked(item):
        actual=identity(item['path'])
        if actual['sha256']!=item['sha256'] or actual['size_bytes']!=item['size_bytes']:raise ValueError('INPUT_IDENTITY_CHANGED:'+item['path'])
        return actual
    checked(request['rules']);rules=json.loads(Path(request['rules']['path']).read_text());checked(request['lowering'])
    if result['operation_status']!='complete' or not result['local_device_released'] or result['errors']:raise ValueError('GPU_RUN_NOT_COMPLETE_OR_RELEASED')
    if len(request['cases'])!=len(rules['references']) or {c['case_id'] for c in request['cases']}!={c['case_id'] for c in result['cases']}:raise ValueError('CASE_COVERAGE')
    comparisons=[];proofs=[];errors=[];raw_artifacts=[]
    def gpu_file(path,expected):
        actual=identity(path)
        if actual['sha256']!=expected:raise ValueError('GPU_RAW_IDENTITY:'+str(path))
        raw_artifacts.append(actual);return actual
    for actual in result['cases']:
        case=next(c for c in request['cases'] if c['case_id']==actual['case_id']);ref=next(r for r in rules['references'] if r['reference_id']==actual['case_id'])
        if actual['execution_mode']!='snapshot' or case['execution_mode']!='snapshot':raise ValueError('WRONG_MODE')
        checked(case['input']);checked(case['snapshot']);checked(case['constants']);checked(ref['baseline'])
        if case['input']['sha256']!=ref['output_seed']['sha256'] or case['snapshot']['sha256']!=ref['snapshot']['sha256'] or case['constants']['sha256']!=ref['constants']['sha256']:raise ValueError('MATCHED_REFERENCE_IDENTITY')
        shader=gpu_file(run/'sources'/Path(case['shader_path']).name,case['shader_sha256'])
        spirv=identity(run/'raw'/(case['case_id']+'_shader.spv'))
        if spirv['size_bytes']==0:raise ValueError('EMPTY_COMPILED_SHADER')
        raw_artifacts.append(spirv);dependency=actual['gpu_dependency_hashes']
        for key,name,item in [('cb','cb_before',case['constants']),('snapshot','snapshot_before',case['snapshot']),('snapshot_after','snapshot_after',case['snapshot'])]:
            if dependency.get(key)!=item['sha256']:raise ValueError('GPU_DEPENDENCY_HASH')
            gpu_file(run/'raw'/(case['case_id']+'_'+name+'.bin'),item['sha256'])
        srvs=case['srvs']
        for slot,item in enumerate(srvs):
            checked(item)
            if item['sha256']!=ref['srvs'][slot]['sha256']:raise ValueError('SRV_REFERENCE_IDENTITY')
            key='texture' if actual['event']==1537 and slot==0 else 'auxiliary';suffix='texture_before' if key=='texture' else 'aux_before'
            if dependency.get(key)!=item['sha256']:raise ValueError('GPU_SRV_HASH')
            gpu_file(run/'raw'/(case['case_id']+'_'+suffix+'.bin'),item['sha256'])
        if len(actual['repeats'])!=request['repeat_count'] or request['repeat_count']!=3:raise ValueError('REPEAT_COVERAGE')
        expected_words=np.fromfile(ref['baseline']['path'],dtype='<u4');expected_codes=codes(ref['baseline']['path'])
        for repeat in actual['repeats']:
            if repeat['sync_end_usec']<repeat['sync_begin_usec'] or repeat['sync_begin_usec']<repeat['submit_begin_usec']:raise ValueError('GPU_COMPLETION_BRACKET')
            if repeat['before_sha256']!=case['input']['sha256']:raise ValueError('GPU_BEFORE_HASH')
            gpu_file(run/'raw'/(case['case_id']+'_'+str(repeat['index'])+'_before.bin'),case['input']['sha256'])
            after=identity(repeat['after'])
            if after['size_bytes']!=2097152:raise ValueError('TRUNCATED_AFTER')
            raw_artifacts.append(after);words=np.fromfile(after['path'],dtype='<u4');decoded=codes(after['path'])
            mismatch=int(np.count_nonzero(words!=expected_words));fields={f:metrics(decoded[f],expected_codes[f]) for f in decoded}
            comparison=dict(reference_id=ref['reference_id'],repeat=repeat['index'],candidate=after,baseline=ref['baseline'],verification_status='passed' if not mismatch else 'failed',
                word_mismatches=mismatch,first_word=int(np.flatnonzero(words!=expected_words)[0]) if mismatch else None,fields=fields,
                scope='Recovered exact snapshot comparison only; no original in-place, sequence or lifecycle acceptance')
            path=out/'comparisons'/(case['case_id']+'_'+str(repeat['index'])+'.json');path.write_text(json.dumps(comparison,indent=2),encoding='utf-8')
            comparisons.append(dict(reference_id=ref['reference_id'],event=actual['event'],repeat=repeat['index'],status=comparison['verification_status'],word_mismatches=mismatch,report=identity(path)))
            if mismatch:errors.append(dict(reference_id=ref['reference_id'],repeat=repeat['index'],word_mismatches=mismatch))
        proofs.append(dict(reference_id=ref['reference_id'],shader=shader,spirv=spirv,dependencies=dependency,all_raw_hashes_checked=True))
    report=dict(operation_status='complete',verification_status='failed' if errors else 'passed',scope='No new GPU process: verification of complete terminal raw run and exact comparisons; no G02/G5 acceptance.',
        original_run=str(run),request=identity(run/'request.json'),gpu_result=identity(run/'raw/probe_result.json'),rules=request['rules'],lowering=request['lowering'],
        original_process_metadata='Wrapper failed after GPU exit; no recovered PID/command claim. Archived launcher source/request and GPU result retained.',
        comparisons=comparisons,proofs=proofs,raw_artifacts=raw_artifacts,errors=errors,device=result['device'],engine_version=result['engine_version'])
    (out/'snapshot_comparison.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    for name in ['evaluate_snapshot_run.py','reference_budget.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/name)
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status=report['verification_status'],artifacts=[identity(p) for p in out.rglob('*') if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(status=report['verification_status'],comparisons=len(comparisons),failed=len(errors),raw_integrity='passed')))
    raise SystemExit(bool(errors))


if __name__=='__main__':main()
