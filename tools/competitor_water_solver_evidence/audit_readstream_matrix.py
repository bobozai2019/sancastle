"""Independent raw-byte, instruction-subsequence and bidirectional read-stream audit."""
import argparse
import json
import re
import shutil
from pathlib import Path
import numpy as np
from evidence_contract import identity
from make_snapshot_dxbc import sections
from lower_dxbc_glsl import split_args,destination


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--completed-prefix',action='store_true',help='Audit only an interrupted full matrix completed prefix; never accepts full coverage.');ap.add_argument('--native-matrix',type=Path);ap.add_argument('--record-matrix',type=Path);ap.add_argument('--full-matrix',type=Path);ap.add_argument('--output',type=Path,required=True)
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False);errors=[];seen={};manifest_cache={};rehashed=0
    def check(a):
        nonlocal rehashed
        if a['path'] not in seen:
            seen[a['path']]=identity(a['path']);rehashed+=1
        actual=seen[a['path']]
        if actual['sha256']!=a['sha256'] or actual['size_bytes']!=a['size_bytes']:raise ValueError('ARTIFACT_CHANGED:'+a['path'])
        return actual
    def manifest(a):
        if isinstance(a,Path):a=identity(a)
        check(a)
        if a['path'] not in manifest_cache:
            m=json.loads(Path(a['path']).read_text())
            if m['operation_status']!='complete' or m['verification_status']!='passed' or m.get('errors'):raise ValueError('MANIFEST_NOT_PASSED:'+a['path'])
            for artifact in m['artifacts']:check(artifact)
            manifest_cache[a['path']]=m
        return manifest_cache[a['path']]
    def packet(a,adapter):
        check(a);count=len(adapter['reads'])
        if a['size_bytes']!=131072*count*32:raise ValueError('STREAM_EXTENT')
        value=np.fromfile(a['path'],dtype='<u4').reshape(131072,count,2,4);meta=value[:,:,0,:]
        if np.any(meta[:,:,0]>=131072):raise ValueError('STREAM_INDEX_DOMAIN')
        for column,key in [(1,'offset'),(2,'mask_bits'),(3,'instruction')]:
            if not np.all(meta[:,:,column]==np.array([r[key] for r in adapter['reads']],dtype='<u4')):raise ValueError('STREAM_METADATA')
        for slot,r in enumerate(adapter['reads']):
            for lane,c in enumerate('xyzw'):
                if c not in r['mask'] and np.any(value[:,slot,1,lane]):raise ValueError('UNRECORDED_LANE_NONZERO')
        return value
    def normal(a):
        check(a)
        if a['size_bytes']!=2097152:raise ValueError('NORMAL_EXTENT')
        return np.fromfile(a['path'],dtype='<u4').reshape(131072,4)
    def stats(raw):
        code=raw[:,2]&0xffffff;a=code.astype('f8')*(10.1/16777215)-.05;h=np.maximum(a,0)
        return dict(A_code_sum=int(code.sum(dtype='u8')),A_decoded_sum=float(a.sum()),visible_h_sum=float(h.sum()),decoded_nonfinite=int(np.count_nonzero(~np.isfinite(a)|~np.isfinite(h))),
            final_categories={name:{str(int(k)):int(v) for k,v in zip(*np.unique(value,return_counts=True))} for name,value in [('B',(raw[:,3]>>16)&255),('source',(raw[:,3]>>24)&15),('sea',raw[:,3]>>28),('wet',(a>0).astype('u1'))]})
    def source_classification(values,initial,completed,adapter):
        totals=dict(initial_only=0,completed_only=0,indistinguishable=0,mixed_components=0,contains_other_word=0)
        for slot,r in enumerate(adapter['reads']):
            index=values[:,slot,0,0];positions=['xyzw'.index(c) for c in r['mask']];swizzle=r['original'].rsplit('u0.',1)[1];source=[r['offset']//4+'xyzw'.index(swizzle[p]) for p in positions]
            observed=values[:,slot,1,:][:,positions];old=initial[index][:,source];new=completed[index][:,source];o=(observed==old);n=(observed==new);oa=o.all(axis=1);na=n.all(axis=1);possible=(o|n).all(axis=1)
            for name,mask in [('initial_only',oa&~na),('completed_only',na&~oa),('indistinguishable',oa&na),('mixed_components',possible&~oa&~na),('contains_other_word',~possible)]:totals[name]+=int(mask.sum())
        return totals
    adapters={}
    def static_adapter(a):
        check(a)
        if a['sha256'] in adapters:return adapters[a['sha256']]
        adapter=json.loads(Path(a['path']).read_text());check(adapter['parent']);check(adapter['parent_asm'])
        _,_,_,original_prefix,original_code,decls,numbered=sections(Path(adapter['parent']['path']).read_bytes(),Path(adapter['parent_asm']['path']).read_text())
        temp_count=int(re.search(r'dcl_temps (\d+)',Path(adapter['parent_asm']['path']).read_text())[1]);extra_counts={}
        for p in adapter['programs']:
            check(p['program']);check(p['assembly'])
            _,_,_,prefix,code,new_decls,new_numbered=sections(Path(p['program']['path']).read_bytes(),Path(p['assembly']['path']).read_text())
            restore=[d for d in new_decls if d not in ['dcl_uav_structured u1, 16','dcl_resource_structured t2, 16']]
            restore=[('dcl_temps '+str(temp_count)) if d.startswith('dcl_temps ') else d for d in restore]
            if restore!=decls:raise ValueError('ORIGINAL_DECLARATION_CHANGED')
            changed={r['instruction'] for r in p['changed_loads']};positions=p['original_positions']
            for i,row in enumerate(original_code):
                if i not in changed and code[positions[i]]!=row:raise ValueError('ORIGINAL_INSTRUCTION_CHANGED')
            extras=[text for i,(_,text) in enumerate(new_numbered) if i not in set(positions)]
            for text in extras:
                op,tail=text.split(' ',1);operands=split_args(tail)
                if op=='store_structured':
                    if operands[0]!='u1.xyzw':raise ValueError('EXTRA_WATER_STORE')
                elif op in ['imad','iadd','mov']:
                    reg,_=destination(operands[0])
                    if int(reg[1:])<temp_count:raise ValueError('EXTRA_ORIGINAL_REGISTER_WRITE')
                else:raise ValueError('UNEXPECTED_INSTRUMENTATION_OPCODE')
            extra_counts[p['mode']]=len(extras)
        adapters[a['sha256']]=(adapter,dict(event=adapter['event'],original_instructions=len(original_code),extra_instructions=extra_counts,programs=[p['program'] for p in adapter['programs']]))
        return adapters[a['sha256']]
    if args.full_matrix:
        if args.completed_prefix:
            top_path=args.full_matrix/'manifest.json';top=json.loads(top_path.read_text());check(identity(top_path));check(top['request'])
            request=json.loads(Path(top['request']['path']).read_text());expected={r['reference_id'] for r in request['fixtures']}
            completed=[r for r in top['fixtures'] if r['status']=='passed']
            if top['operation_status'] not in ['running','interrupted'] or len(expected)!=72 or not 0<len(completed)<72:raise ValueError('NOT_INCOMPLETE_PREFIX')
            if [r['reference_id'] for r in completed]!=[r['reference_id'] for r in request['fixtures'][:len(completed)]]:raise ValueError('PREFIX_IDENTITY_ORDER')
            if [r['ordinal'] for r in completed]!=list(range(len(completed))):raise ValueError('PREFIX_ORDINAL_ORDER')
            selected=completed
        else:
            top=manifest(args.full_matrix/'manifest.json');request=json.loads(Path(top['request']['path']).read_text());expected={r['reference_id'] for r in request['fixtures']}
            if len(expected)!=72 or {r['reference_id'] for r in top['fixtures']}!=expected:raise ValueError('FULL_FIXTURE_COVERAGE')
            selected=top['fixtures']
        items=[(r['reference_id'],r['event'],r['native'],r['godot'],r['alias']) for r in selected]
    else:
        top=manifest(args.native_matrix/'manifest.json');reverse=manifest(args.record_matrix/'manifest.json')
        if len(top['kernels'])!=6 or {k['event'] for k in top['kernels']}!={1484,1490,1495,1500,1537,1543}:raise ValueError('SIX_KERNEL_COVERAGE')
        items=[]
        for k in top['kernels']:
            r=next(r for r in reverse['kernels'] if r['event']==k['event']);n=manifest(k['native']);q=json.loads(Path(n['request']['path']).read_text());items.append((q['reference_id'],k['event'],k['native'],k['godot'],r['record']))
    rows=[];counts=dict(native_captures=0,native_replays=0,godot_forward_replays=0,godot_alias_captures=0,native_reverse_replays=0)
    for reference_id,event,nref,gref,aref in items:
        n=manifest(nref);g=manifest(gref);a=manifest(aref);nq=json.loads(Path(n['request']['path']).read_text());gq=json.loads(Path(g['request']['path']).read_text());aq=json.loads(Path(a['request']['path']).read_text())
        adapter,static=static_adapter(nq['adaptation']);initial=normal(nq['input']);check(nq['constants'])
        if nq['event']!=event or nq['reference_id']!=reference_id or gq['reference']['sha256']!=nref['sha256'] or aq['fixture_reference']['sha256']!=nref['sha256']:raise ValueError('REFERENCE_PARENT_LINK')
        for artifact in nq['srvs']:check(artifact)
        if len(n['capture']['checks'])!=3 or len(n['replays'])!=3 or len(g['comparisons'])!=9 or len(a['records'])!=3:raise ValueError('PAIR_COVERAGE')
        for owner,key in [(n,'negatives'),(g,'negatives'),(a,'guards')]:
            if not owner[key] or not all(t['passed'] for t in owner[key]):raise ValueError('GUARD_COVERAGE')
            for t in owner[key]:
                if 'reused_from' in t:
                    previous=manifest(t['reused_from']);guard_key='guards' if key=='guards' else 'negatives'
                    if not any(p['case']==t['case'] and p['passed'] for p in previous[guard_key]):raise ValueError('GUARD_RECEIPT_LINK')
        native_values=[];native_outputs=[];classifications=[];aggregate=[]
        cap_root=Path(n['capture']['run']['output']);logs=[json.loads(x) for x in (cap_root/'execution.jsonl').read_text().splitlines()]
        for cap in n['capture']['checks']:
            i=cap['repeat'];before=check(cap['before']);output=normal(cap['after']);stream=packet(cap['stream'],adapter)
            if before['sha256']!=nq['input']['sha256'] or logs[i]['fence_completed']<logs[i]['fence_ticket']:raise ValueError('NATIVE_CAPTURE_COMPLETION')
            if len(cap['original_srvs_before'])!=len(nq['srvs']):raise ValueError('NATIVE_SRV_COVERAGE')
            for srv,expected in zip(cap['original_srvs_before'],nq['srvs']):
                check(srv)
                if srv['sha256']!=expected['sha256']:raise ValueError('NATIVE_SRV_PROOF')
            replay=next(r for r in n['replays'] if r['capture_repeat']==i);check(replay['check']['after']);check(replay['check']['stream'])
            if replay['check']['after']['sha256']!=cap['after']['sha256'] or replay['check']['stream']['sha256']!=cap['stream']['sha256']:raise ValueError('NATIVE_FORWARD_PAIR')
            rp=Path(replay['run']['output']);log=json.loads((rp/'execution.jsonl').read_text().splitlines()[0])
            if identity(rp/'srv2_before_0.bin')['sha256']!=cap['stream']['sha256'] or log['fence_completed']<log['fence_ticket']:raise ValueError('NATIVE_FORWARD_INPUT')
            native_values.append(stream);native_outputs.append(output);classifications.append(dict(owner='native',repeat=i,classification=source_classification(stream,initial,output,adapter)));aggregate.append(dict(owner='native',repeat=i,statistics=stats(output)))
        for c in g['comparisons']:
            check(c['report']);detail=json.loads(Path(c['report']['path']).read_text());check(detail['candidate']);check(detail['native']);check(detail['stream']);check(detail['native_stream'])
            if detail['candidate']['sha256']!=detail['native']['sha256'] or detail['stream']['sha256']!=detail['native_stream']['sha256']:raise ValueError('GODOT_FORWARD_PAIR')
        if not g['gpu_result']['local_device_released'] or not a['gpu_result']['local_device_released']:raise ValueError('GODOT_RESOURCES_NOT_RELEASED')
        alias_root=Path(aref['path']).parent
        alias_result=a['gpu_result']['cases'][0]
        if alias_result['execution_mode']!='in_place_record' or 'stream_input' in alias_result['gpu_dependency_hashes']:raise ValueError('NOT_GODOT_OWN_ALIAS')
        for r in a['records']:
            check(r['before']);go=normal(r['godot_normal']);gs=packet(r['godot_stream'],adapter);normal(r['native_normal']);packet(r['native_stream'],adapter)
            if r['before']['sha256']!=nq['input']['sha256'] or r['godot_normal']['sha256']!=r['native_normal']['sha256'] or r['godot_stream']['sha256']!=r['native_stream']['sha256']:raise ValueError('GODOT_REVERSE_PAIR')
            rp=alias_root/'native'/('replay_'+str(r['repeat']));log=json.loads((rp/'execution.jsonl').read_text().splitlines()[0])
            if identity(rp/'srv2_before_0.bin')['sha256']!=r['godot_stream']['sha256'] or log['fence_completed']<log['fence_ticket']:raise ValueError('NATIVE_REVERSE_INPUT')
            classifications.append(dict(owner='godot',repeat=r['repeat'],classification=source_classification(gs,initial,go,adapter)));aggregate.append(dict(owner='godot',repeat=r['repeat'],statistics=stats(go)))
        for owner,receipt,req in [('godot_forward',g,gq),('godot_alias',a,aq)]:
            directory=Path(gref['path']).parent if owner=='godot_forward' else alias_root
            for actual in receipt['gpu_result']['cases']:
                case=next(c for c in req['cases'] if c['case_id']==actual['case_id']);deps=actual['gpu_dependency_hashes']
                if deps['cb']!=case['constants']['sha256'] or identity(directory/'raw'/(case['case_id']+'_cb_before.bin'))['sha256']!=case['constants']['sha256']:raise ValueError('GODOT_CB_PROOF')
                for slot,srv in enumerate(case['srvs']):
                    key='texture' if event==1537 and slot==0 else 'auxiliary';suffix='texture_before' if key=='texture' else 'aux_before'
                    if deps[key]!=srv['sha256'] or identity(directory/'raw'/(case['case_id']+'_'+suffix+'.bin'))['sha256']!=srv['sha256']:raise ValueError('GODOT_SRV_PROOF')
                if owner=='godot_forward':
                    for suffix,key in [('stream_input_before','stream_input'),('stream_input_after','stream_input_after')]:
                        if deps[key]!=case['stream_input']['sha256'] or identity(directory/'raw'/(case['case_id']+'_'+suffix+'.bin'))['sha256']!=case['stream_input']['sha256']:raise ValueError('READONLY_STREAM_PROOF')
                spirv=identity(directory/'raw'/(case['case_id']+'_shader.spv'));shader=identity(directory/'sources'/Path(case['shader_path']).name)
                if not spirv['size_bytes'] or shader['sha256']!=case['shader_sha256']:raise ValueError('COMPILED_SHADER_PROOF')
                for repeat in actual['repeats']:
                    if repeat['before_sha256']!=nq['input']['sha256'] or not repeat['submit_begin_usec']<=repeat['sync_begin_usec']<=repeat['sync_end_usec']:raise ValueError('GODOT_INPUT_OR_COMPLETION')
        counts['native_captures']+=3;counts['native_replays']+=3;counts['godot_forward_replays']+=9;counts['godot_alias_captures']+=3;counts['native_reverse_replays']+=3
        rows.append(dict(reference_id=reference_id,event=event,read_count=len(adapter['reads']),static=static,input_statistics=stats(initial),output_statistics=aggregate,loaded_value_classifications=classifications,
            native_distinct_outputs=len({r['after']['sha256'] for r in n['capture']['checks']}),godot_distinct_outputs=len({r['godot_normal']['sha256'] for r in a['records']}),normal_and_stream_exact=True))
        print(json.dumps(dict(audited=len(rows),total=len(items),event=event)),flush=True)
    result=dict(operation_status='complete',verification_status='passed' if not errors else 'failed',fixtures=len(rows),counts=counts,artifacts_rehashed=rehashed,rows=rows,errors=errors,
        coverage=dict(requested=72 if args.full_matrix else 6,audited=len(rows),full_matrix_accepted=bool(args.full_matrix and not args.completed_prefix),completed_prefix_only=bool(args.completed_prefix)),
        scope='Byte/input/completion/source-instruction audit of instrumented bidirectional alias read-stream pairing only. Initial/completed word classifications are diagnostic, not atomicity or a universal schedule/timestamp proof. No short-sequence/lifecycle acceptance.',
        aggregate_units='A_decoded=code*10.1/16777215-.05; h=max(A_decoded,0), no area/volume factor. Internal floating intermediates and source/clamp/boundary decomposition not inferred from packed output.',
        source_clamp_boundary_contribution_decomposition=None)
    (out/'audit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    for name in ['audit_readstream_matrix.py','make_snapshot_dxbc.py','probe_dxbc_rebuild.py','lower_dxbc_glsl.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/name)
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status=result['verification_status'],artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(status=result['verification_status'],fixtures=len(rows),counts=counts,rehashes=rehashed)))


if __name__=='__main__':main()
