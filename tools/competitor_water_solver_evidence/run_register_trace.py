"""Pair register observations and test whether observing changes normal output."""
import argparse
import datetime
import json
import shutil
import subprocess
from pathlib import Path
import numpy as np
from evidence_contract import identity


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for key in ['trace','build','rules','godot-baseline','output']:ap.add_argument('--'+key,type=Path,required=True)
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    root=Path(__file__).resolve().parents[3];project=root/'tests/investigation/water_solver_evidence_probe'
    def checked(item):
        now=identity(item['path'])
        if now['sha256']!=item['sha256'] or now['size_bytes']!=item['size_bytes']:raise ValueError('FROZEN_SOURCE_CHANGED:'+item['path'])
        return item
    def checked_manifest(directory,name):
        parent=json.loads((directory/'manifest.json').read_text())
        return checked(next(i for i in parent['artifacts'] if Path(i['path']).name==name))
    checked_manifest(args.trace,'trace.json');trace=json.loads((args.trace/'trace.json').read_text())
    if trace['event'] not in [1490,1500]:raise ValueError('TRACE_PILOT_ONLY_SIMPLE_KERNELS')
    program=checked(trace['program']);shader=checked(trace['glsl'])
    executable=checked_manifest(args.build,'water_trace_reference.exe')
    checked_manifest(args.rules.parent,args.rules.name);rules=json.loads(args.rules.read_text())
    ref=next(r for r in rules['references'] if r['event_id']==trace['event'])
    for item in [ref['snapshot'],ref['output_seed'],ref['constants'],ref['baseline']]:checked(item)
    if ref['srvs']:raise ValueError('UNMODELED_TRACE_AUXILIARY_INPUT')
    if ref['adapted_program']['sha256']!=trace['parent']['adapted']['sha256']:raise ValueError('PARENT_ADAPTER_MISMATCH')
    checked_manifest(args.godot_baseline,'snapshot_comparison.json')
    old=json.loads((args.godot_baseline/'snapshot_comparison.json').read_text())
    old_item=next(c for c in old['comparisons'] if c['reference_id']==ref['reference_id'] and c['repeat']==0)
    checked(old_item['report']);old_comparison=json.loads(Path(old_item['report']['path']).read_text());checked(old_comparison['candidate'])
    # Freeze all requested inputs before either GPU process starts.
    request=dict(trace=identity(args.trace/'trace.json'),build=identity(args.build/'manifest.json'),rules=identity(args.rules),
                 godot_unobserved_baseline=old_comparison['candidate'],reference=ref,repeat_count=3,
                 scope='Explicit observed snapshot arithmetic. Check normal output before interpreting intermediate values.')
    (out/'request.json').write_text(json.dumps(request,indent=2),encoding='utf-8')
    sources=out/'sources';sources.mkdir()
    for p in [*project.glob('*.gd'),*project.glob('*.tscn'),project/'project.godot',Path(shader['path']),Path(__file__)]:shutil.copyfile(p,sources/p.name)
    native_command=[executable['path'],'--program',program['path'],'--snapshot',ref['snapshot']['path'],'--input',ref['output_seed']['path'],
        '--constants',ref['constants']['path'],'--output',(out/'native').as_posix(),'--kind','simple','--repeat','3','--before-copy','1']
    records=[]
    def run(command,name):
        start=datetime.datetime.now(datetime.timezone.utc).isoformat();p=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,creationflags=subprocess.CREATE_NO_WINDOW)
        try:stdout,stderr=p.communicate(timeout=120)
        except subprocess.TimeoutExpired:p.kill();stdout,stderr=p.communicate();raise RuntimeError('OWNED_TRACE_TIMEOUT')
        (out/(name+'_stdout.bin')).write_bytes(stdout);(out/(name+'_stderr.bin')).write_bytes(stderr)
        records.append(dict(command=command,pid=p.pid,exit_code=p.returncode,started_at=start,finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat()))
        if p.returncode:
            (out/'trace_audit.json').write_text(json.dumps(dict(operation_status='failed',verification_status='not_evaluated',processes=records,error='TRACE_PROCESS_FAILED:'+name),indent=2),encoding='utf-8')
            (out/'manifest.json').write_text(json.dumps(dict(operation_status='failed',verification_status='not_evaluated',artifacts=[identity(p) for p in out.rglob('*') if p.is_file()]),indent=2),encoding='utf-8')
            raise ValueError('TRACE_PROCESS_FAILED:'+name)
    run(native_command,'native')
    case=dict(case_id=ref['reference_id'],event_id=trace['event'],execution_mode='snapshot',register_trace=True,
        shader_path='res://shaders/'+Path(shader['path']).name,shader_sha256=shader['sha256'],input=ref['output_seed'],snapshot=ref['snapshot'],constants=ref['constants'],srvs=[])
    godot_request=dict(schema_version='1.0',repeat_count=3,output_root=(out/'godot').as_posix(),cases=[case])
    (out/'godot').mkdir()
    file=out/'godot_request.json';file.write_text(json.dumps(godot_request,indent=2),encoding='utf-8')
    godot=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe')
    run([str(godot),'--path',str(project),'--rendering-method','mobile','--rendering-driver','vulkan','--log-file',str(out/'engine.log'),'res://kernel_probe.tscn','--','--request',str(file)],'godot')
    result=json.loads((out/'godot/probe_result.json').read_text());actual=result['cases'][0]
    errors=[];rows=[]
    if result['operation_status']!='complete':errors.append('GODOT_INCOMPLETE')
    if actual['gpu_dependency_hashes'].get('snapshot')!=ref['snapshot']['sha256'] or actual['gpu_dependency_hashes'].get('snapshot_after')!=ref['snapshot']['sha256'] or actual['gpu_dependency_hashes'].get('cb')!=ref['constants']['sha256']:errors.append('GODOT_DEPENDENCY_MISMATCH')
    native_logs=[json.loads(s) for s in (out/'native/execution.jsonl').read_text().splitlines()]
    for repeat in range(3):
        native=out/'native';prefix=out/'godot'/(ref['reference_id']+'_'+str(repeat))
        if identity(native/f'before_{repeat}.bin')['sha256']!=ref['output_seed']['sha256'] or identity(native/f'srv2_before_{repeat}.bin')['sha256']!=ref['snapshot']['sha256']:errors.append('NATIVE_GPU_INPUT_MISMATCH')
        if native_logs[repeat]['fence_completed']<native_logs[repeat]['fence_ticket']:errors.append('NATIVE_FENCE_INCOMPLETE')
        if actual['repeats'][repeat]['before_sha256']!=ref['output_seed']['sha256']:errors.append('GODOT_GPU_INPUT_MISMATCH')
        nout=identity(native/f'after_{repeat}.bin');gout=identity(str(prefix)+'_after.bin')
        native_same=nout['sha256']==ref['baseline']['sha256'];godot_same=gout['sha256']==old_comparison['candidate']['sha256']
        ntrace=identity(native/f'trace_{repeat}.bin');gtrace=identity(str(prefix)+'_trace.bin')
        n=np.fromfile(ntrace['path'],dtype='<u4').reshape(-1,4);g=np.fromfile(gtrace['path'],dtype='<u4').reshape(-1,4)
        diffs=np.argwhere(n!=g)
        points=[]
        for cell,lane in diffs[:24]:
            points.append(dict(x=int(cell%512),z=int(cell//512),lane='xyzw'[lane],native_word=hex(int(n[cell,lane])),godot_word=hex(int(g[cell,lane])),native_float=float(n.view('<f4')[cell,lane]),godot_float=float(g.view('<f4')[cell,lane])))
        rows.append(dict(repeat=repeat,native_normal=nout,godot_normal=gout,native_normal_matches_unobserved=native_same,godot_normal_matches_unobserved=godot_same,
            native_trace=ntrace,godot_trace=gtrace,trace_word_mismatches=len(diffs),trace_examples=points,
            interpretable_as_unobserved_arithmetic=native_same and godot_same))
    stable=len({r['native_trace']['sha256'] for r in rows})==1 and len({r['godot_trace']['sha256'] for r in rows})==1
    report=dict(operation_status='complete',verification_status='passed' if not errors else 'failed',scope='Diagnostic integrity only; no G02/G5 acceptance.',
        request=identity(out/'request.json'),processes=records,rows=rows,trace_repeats_stable=stable,errors=errors,
        observation_preserves_both_normal_outputs=all(r['interpretable_as_unobserved_arithmetic'] for r in rows))
    (out/'trace_audit.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status=report['verification_status'],artifacts=[identity(p) for p in out.rglob('*') if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(status=report['verification_status'],stable=stable,preserves_normal=report['observation_preserves_both_normal_outputs'],trace_word_mismatches=rows[0]['trace_word_mismatches'])))
    raise SystemExit(bool(errors))


if __name__=='__main__':main()
