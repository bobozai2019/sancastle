"""Index/audit six controlled original-DXBC references and copy perturbation."""
import argparse
import json
import re
import shutil
from pathlib import Path
from evidence_contract import identity
from run_native_suite import STAGES


def write(path,data):path.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite',required=True,type=Path);parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args();out=args.output
    if not out.is_absolute() or not str(out).isascii():raise ValueError('Absolute ASCII output required')
    out.mkdir(parents=True,exist_ok=False)
    for name in ['sources','derived','raw','logs']:(out/name).mkdir()
    suite=json.loads((args.suite/'manifest.json').read_text());errors=[];checks=[];reference_set=[];artifacts=[]
    if suite['operation_status']!='complete' or suite['errors']:errors.append('SUITE_NOT_COMPLETE')
    for a in suite['artifacts']:
        actual=identity(a['path']);valid=actual['sha256']==a['sha256'] and actual['size_bytes']==a['size_bytes']
        checks.append(dict(path=a['path'],valid=valid))
        if not valid:errors.append('ARTIFACT_CHANGED:'+a['path'])
    source_id='rdc:761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2'
    for ref in suite['references']:
        req=ref['request'];root=Path(req['output']);eid=req['event_id']
        refl=json.loads((root/'reflection.json').read_text());execution=[json.loads(s) for s in (root/'execution.jsonl').read_text().splitlines()]
        assembly=(root/'original_program.asm').read_text()
        if identity(req['program']['path'])['sha256']!=STAGES[eid][2]:errors.append('PROGRAM_MISMATCH:'+str(eid))
        if refl['declared_cbv_bytes']!=req['constants']['size_bytes']:errors.append('CBV_DECLARATION_MISMATCH')
        if not re.search(r'dcl_uav_structured u0, 16',assembly) or re.search(r'alloc|consume|dcl_sampler|structured_opc',assembly):errors.append('COUNTER_OR_LAYOUT_MISMATCH')
        if len(execution)!=3 or len(ref['checks'])!=3:errors.append('REPEAT_COUNT_MISMATCH')
        for log,c in zip(execution,ref['checks']):
            if log['srv_count']!=len(req['srvs']) or log['constant_bytes']!=req['constants']['size_bytes'] or not c['fence_complete']:errors.append('EXECUTION_DEPENDENCY_MISMATCH')
            if req['before_copy']:
                if c['before']['sha256']!=req['input']['sha256']:errors.append('WATER_RESTORATION_FAILED')
                for index,srv in enumerate(req['srvs']):
                    if c['srv_snapshots'][index]['sha256']!=srv['sha256']:errors.append('SRV_RESTORATION_FAILED')
        selector=dict(capture_sha256=source_id[4:],event_id=eid,stage='compute',phase='single_dispatch_controlled',
            shader_sha256=req['program']['sha256'],dispatch=[16,8,1],threads=[32,32,1])
        def artifact(path,kind,detail=None,parents=None):
            path=Path(path);key='suite/'+path.relative_to(args.suite).as_posix()
            if not any(a['artifact_id']==key for a in artifacts):
                actual=identity(path);selected=dict(detail or selector)
                if kind=='raw_snapshot':
                    binding=selected.get('binding')
                    if isinstance(binding,dict) and 'texture' in binding:
                        selected['texture_view']=dict(binding['texture'],mip=0,array_slice=0,plane=0,row_pitch=2048)
                    else:
                        stride=16 if not isinstance(binding,str) else 1
                        selected['buffer_view']=dict(byte_offset=0,byte_length=actual['size_bytes'],stride=stride,
                            element_count=actual['size_bytes']//stride,format='uint4' if stride==16 else 'bytes')
                artifacts.append(dict(actual,artifact_id=key,kind=kind,source_ids=[source_id],parent_artifact_ids=parents or [],selector=selected,completeness='complete'))
            return key
        program_id=artifact(req['program']['path'],'program')
        input_id=artifact(req['input']['path'],'raw_snapshot',dict(selector,boundary='frozen controlled seed',source_post_event=req['feed_event_id']))
        cb_id=artifact(req['constants']['path'],'raw_snapshot',dict(selector,binding='b0',byte_length=req['constants']['size_bytes']))
        srv_ids=[artifact(srv['path'],'raw_snapshot',dict(selector,binding=srv['selector'])) for srv in req['srvs']]
        dependency_ids=[program_id,input_id,cb_id]+srv_ids
        proof=[artifact(root/'execution.jsonl','log'),artifact(root/'reflection.json','decoded'),artifact(root/'original_program.asm','decoded',parents=[program_id])]
        outputs=[]
        for c in ref['checks']:
            outputs.append(artifact(c['output']['path'],'raw_snapshot',dict(selector,boundary='after dispatch and completed GPU fence',repeat=c['repeat']),dependency_ids))
            if req['before_copy']:
                proof.append(artifact(c['before']['path'],'raw_snapshot',dict(selector,boundary='same command list immediately before original dispatch',repeat=c['repeat']),[input_id]))
                for index,s in enumerate(c['srv_snapshots']):proof.append(artifact(s['path'],'raw_snapshot',dict(selector,boundary='read-only dependency snapshot before dispatch',repeat=c['repeat'],binding=req['srvs'][index]['selector']),srv_ids))
        reference_set.append(dict(reference_id=req['reference_id'],source_manifest=identity(args.suite/'manifest.json'),
            input_artifact_ids=[input_id,cb_id]+srv_ids,output_artifact_ids=outputs,program_artifact_id=program_id,
            dependencies_complete=True,dependency_coverage=dict(CBV='b0: exact executable-declared extent',UAV='u0 131072 uint4 stride16 same-resource read/write',
                SRV=[s['selector'] for s in req['srvs']],samplers='none in executable declarations',counters='none; no counter declaration or alloc/consume instructions'),
            pairing=dict(pairing_kind='reconstructed_controlled',proof_artifact_ids=proof,
                method='Restored immutable seed and dependency uploads, same command list single dispatch and completed fence. GPU before-copy proof where enabled; no-copy variant has identical restore commands and program with the instrument copy disabled.'),
            original_root_signature='Equivalent register/space bindings reconstructed, not original serialized root-signature bytes',
            copy_instrumentation=req['before_copy'],mode='original_program_in_place',
            field_layout='Native 512x256 packed uint4; see current water field specification',
            limitations=['Fixture selected from replay post-state, not original same-execution pre-state',
                'Only this NVIDIA adapter/driver and measured fixtures', 'Buffer SRVs are immutable UPLOAD resources; original heap placement unknown',
                'Three repeats and copy-on/off comparison are observed samples, not a universal statistical bound'],
            original_request_metadata_erratum='hidden_counters text mentions D3DReflect; actual authoritative validation is executable declarations because all six original programs have zero RDEF reflection entries.'))
    metrics=json.loads((args.suite/'derived/repeat_and_copy_metrics.json').read_text());summary=[]
    for eid in STAGES:
        for comparison,copy in [('within_mode',True),('within_mode',False),('copy_perturbation',None)]:
            group=[r['metric'] for r in metrics if r['event_id']==eid and r['comparison']==comparison and (copy is None or r['before_copy']==copy)]
            summary.append(dict(event_id=eid,comparison=comparison,before_copy=copy,pairs=len(group),
                changed_cells_min=min(x['changed_cells'] for x in group),changed_cells_max=max(x['changed_cells'] for x in group),
                field_maxima={field:max(x['fields'][field]['max'] for x in group) for field in group[0]['fields']}))
    compiler_paths=[]
    log=(args.suite/'sources/build_stdout.bin').read_bytes().decode('utf-8',errors='replace')
    for match in re.findall(r'([A-Za-z]:[^\r\n]*?\\(?:cl|link)\.exe)',log):
        if match not in compiler_paths:compiler_paths.append(match)
    write(out/'derived/toolchain.json',dict(compiler_files=[identity(p) for p in compiler_paths],raw_build_log=identity(args.suite/'sources/build_stdout.bin'),
        limitation='SDK include/lib selection is not printed in this build; build source and command are preserved. No claim of exact SDK minor version.'))
    write(out/'reference_set.json',dict(schema_version='1.0',references=reference_set,artifacts=artifacts,errors=errors,numeric_budget=None))
    write(out/'derived/repeat_and_copy_summary.json',summary);write(out/'derived/file_checks.json',checks)
    for name in ['audit_native_suite.py','run_native_suite.py','evidence_contract.py','analyze_repeats.py']:
        shutil.copyfile(Path(__file__).with_name(name),out/'sources'/name)
    write(out/'manifest.json',dict(schema_version='1.0',run_id=out.name,operation_status='complete',verification_status='failed' if errors else 'passed',
        input_manifest=identity(args.suite/'manifest.json'),errors=errors,artifacts=[identity(p) for p in out.rglob('*') if p.is_file()],
        scope='T03-G02 tool and G03 six-kernel controlled-reference coverage only; G04 budgets and threshold cases still pending'))
    print(json.dumps(dict(errors=errors,references=len(reference_set),checked_files=len(checks))))
    raise SystemExit(1 if errors else 0)


if __name__=='__main__':main()
