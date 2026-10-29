"""Audit paired velocity read-stream evidence, including old failed guard and repair.

Classify observed loaded words against input/completed output, without assuming
vector atomicity, a global schedule, or exact timing from the classifications.
"""
import argparse
import json
import shutil
from pathlib import Path
import numpy as np
from evidence_contract import identity


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['reference','godot','guard','output']:ap.add_argument('--'+name,type=Path,required=True)
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False);errors=[];checked_count=0
    def verify_manifest(path):
        nonlocal checked_count
        manifest=json.loads(path.read_text())
        for a in manifest['artifacts']:
            actual=identity(a['path'])
            if actual['sha256']!=a['sha256'] or actual['size_bytes']!=a['size_bytes']:errors.append('ARTIFACT_CHANGED:'+a['path'])
            checked_count+=1
        return manifest
    native=verify_manifest(args.reference);godot=verify_manifest(args.godot);guard_manifest=verify_manifest(args.guard.parent/'manifest.json');guard=json.loads(args.guard.read_text())
    if native['verification_status']!='passed' or native['errors'] or not all(r['normal_output_exact'] and r['stream_exact'] for r in native['replays']) or not all(n['passed'] for n in native['negatives']):errors.append('NATIVE_PAIRED_REFERENCE_NOT_VALID')
    for replay in native['replays']:
        capture=next(r for r in native['capture']['checks'] if r['repeat']==replay['capture_repeat'])
        if replay['check']['after']['sha256']!=capture['after']['sha256'] or replay['check']['stream']['sha256']!=capture['stream']['sha256']:errors.append('NATIVE_REPLAY_HASH_RELATION')
    if godot['operation_status']!='complete' or godot['errors']!=['NEGATIVE_NOT_REJECTED:wrong_identity']:errors.append('UNEXPECTED_OLD_GODOT_FAILURE')
    if len(godot['comparisons'])!=9 or any(c['status']!='passed' for c in godot['comparisons']):errors.append('POSITIVE_GODOT_COVERAGE')
    if guard['verification_status']!='passed' or guard_manifest['verification_status']!='passed' or not guard['result']['local_device_released']:errors.append('REPAIRED_GUARD_NOT_VALID')
    if 'checks' in guard and (not all(c['passed'] for c in guard['checks']) or not any(c['case']=='empty_stream' for c in guard['checks'])):errors.append('EMPTY_STREAM_GUARD_NOT_VALID')
    if not all(n['passed'] for n in godot['negatives'] if n['case']!='wrong_identity'):errors.append('OTHER_GODOT_GUARD_NOT_VALID')
    old_probe=(args.godot.parent/'sources/stream_probe.gd').read_text()
    repaired_probe=(args.guard.parent/'stream_probe.gd').read_text()
    anchor='\t\t\tstream_input_seed = _checked_bytes(case["stream_input"])'
    expected_probe=old_probe.replace(anchor,anchor+'\n\t\t\tif stream_input_seed.is_empty():\n\t\t\t\treturn')
    if 'checks' in guard:
        empty_anchor='\tvar bytes := FileAccess.get_file_as_bytes(str(artifact["path"]))'
        expected_probe=expected_probe.replace(empty_anchor,empty_anchor+'\n\tif bytes.is_empty():\n\t\t_fail("EMPTY_ARTIFACT:" + str(artifact["path"]))\n\t\treturn PackedByteArray()')
    if repaired_probe!=expected_probe:errors.append('GUARD_REPAIR_CHANGED_OTHER_PROBE_CODE')
    request=json.loads(Path(native['request']['path']).read_text());adaptation=json.loads(Path(request['adaptation']['path']).read_text())
    if adaptation['event']!=1490:raise ValueError('VELOCITY_PILOT_ONLY')
    initial=np.fromfile(request['input']['path'],dtype='<u4').reshape(131072,4);classifications=[];streams=[];outputs=[]
    for row in native['capture']['checks']:
        values=np.fromfile(row['stream']['path'],dtype='<u4').reshape(131072,5,2,4);after=np.fromfile(row['after']['path'],dtype='<u4').reshape(131072,4);slots=[]
        streams.append(values);outputs.append(after)
        for r in adaptation['reads']:
            slot=r['slot'];index=values[:,slot,0,0];swizzle=r['original'].rsplit('u0.',1)[1];positions=['xyzw'.index(c) for c in r['mask']]
            source_positions=[r['offset']//4+'xyzw'.index(swizzle[p]) for p in positions]
            observed=values[:,slot,1,:][:,positions];before_value=initial[index][:,source_positions];final_value=after[index][:,source_positions]
            equal_old=observed==before_value;equal_final=observed==final_value;all_old=equal_old.all(axis=1);all_final=equal_final.all(axis=1);each_possible=(equal_old|equal_final).all(axis=1)
            masks=dict(initial_only=all_old&~all_final,completed_only=all_final&~all_old,indistinguishable=all_old&all_final,mixed_components=each_possible&~all_old&~all_final,contains_other_word=~each_possible)
            examples={}
            for name,mask in masks.items():
                coordinates=np.flatnonzero(mask)[:3]
                examples[name]=[dict(invocation=[int(i%512),int(i//512)],source_index=int(index[i]),loaded=[hex(int(x)) for x in observed[i]],initial=[hex(int(x)) for x in before_value[i]],completed=[hex(int(x)) for x in final_value[i]]) for i in coordinates]
            slots.append(dict(slot=slot,instruction=r['instruction'],valid_lanes=r['mask'],tuple_classification={k:int(v.sum()) for k,v in masks.items()},
                word_classification=dict(initial_only=int(np.count_nonzero(equal_old&~equal_final)),completed_only=int(np.count_nonzero(equal_final&~equal_old)),indistinguishable=int(np.count_nonzero(equal_old&equal_final)),neither=int(np.count_nonzero(~equal_old&~equal_final))),examples=examples))
        classifications.append(dict(capture_repeat=row['repeat'],normal_output=row['after'],stream=row['stream'],slots=slots))
    pairwise=[]
    for i in range(len(streams)):
        for j in range(i+1,len(streams)):
            pairwise.append(dict(capture_pair=[i,j],normal_word_differences=int(np.count_nonzero(outputs[i]!=outputs[j])),metadata_word_differences=int(np.count_nonzero(streams[i][:,:,0,:]!=streams[j][:,:,0,:])),loaded_word_differences=int(np.count_nonzero(streams[i][:,:,1,:]!=streams[j][:,:,1,:]))))
    # Verify all positive Godot transport files against corresponding capture, not just old PASS.
    positive=[];root=args.godot.parent;gpu=godot['gpu_result'];g_request=json.loads(Path(godot['request']['path']).read_text())
    if not gpu['local_device_released'] or len(gpu['cases'])!=3:errors.append('GODOT_COMPLETION_OR_CASE_COVERAGE')
    for case in g_request['cases']:
        actual=next(c for c in gpu['cases'] if c['case_id']==case['case_id']);deps=actual['gpu_dependency_hashes']
        for suffix,item,key in [('cb_before',case['constants'],'cb'),('stream_input_before',case['stream_input'],'stream_input'),('stream_input_after',case['stream_input'],'stream_input_after')]:
            a=identity(root/'raw'/(case['case_id']+'_'+suffix+'.bin'))
            if a['sha256']!=item['sha256'] or deps[key]!=item['sha256']:errors.append('GODOT_GPU_DEPENDENCY_CHANGED')
        shader=identity(root/'sources/e1490_read_stream.glsl');spirv=identity(root/'raw'/(case['case_id']+'_shader.spv'))
        if shader['sha256']!=case['shader_sha256'] or spirv['size_bytes']==0:errors.append('SHADER_PROOF_MISSING')
        for repeat in actual['repeats']:
            before=identity(root/'raw'/(case['case_id']+'_'+str(repeat['index'])+'_before.bin'));normal=identity(repeat['after']);stream=identity(root/'raw'/(case['case_id']+'_'+str(repeat['index'])+'_stream_output.bin'))
            if before['sha256']!=case['input']['sha256'] or normal['sha256']!=case['native_output']['sha256'] or stream['sha256']!=case['stream_input']['sha256']:errors.append('GODOT_PAIRED_BYTES_NOT_EXACT')
            if not(repeat['submit_begin_usec']<=repeat['sync_begin_usec']<=repeat['sync_end_usec']):errors.append('GODOT_COMPLETION_BRACKET')
            positive.append(dict(case=case['case_id'],repeat=repeat['index'],normal=normal,stream=stream,shader=shader,spirv=spirv))
    report=dict(operation_status='complete',verification_status='passed' if not errors else 'failed',reference=identity(args.reference),godot=identity(args.godot),repaired_guard=identity(args.guard),
        artifacts_rehashed=checked_count,guard_repair_only_empty_input_return=repaired_probe==expected_probe,native_capture_count=3,native_replay_count=3,godot_paired_count=len(positive),positive=positive,capture_pairs=pairwise,loaded_value_classification=classifications,errors=errors,
        scope='Observed instrumented original u0 alias reads and per-capture arithmetic pairing only. Three native outputs differ, each fixed stream replays exactly. No unmodified-original perturbation equivalence, vector atomicity, universal legal schedule, sequence or lifecycle claim.',
        classification_limits='Initial/completed equality is a value classification, not a timestamp. Equal words are ambiguous. Other/mixed values do not by themselves establish a memory-model or race mechanism.')
    (out/'pairing.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    for name in ['audit_readstream_pairing.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/name)
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status=report['verification_status'],artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(status=report['verification_status'],rehashes=checked_count,native_replays=3,godot_pairs=len(positive),capture_pairs=pairwise,errors=errors[:3])))
    raise SystemExit(bool(errors))


if __name__=='__main__':main()
