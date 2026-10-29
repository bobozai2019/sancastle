"""Compare explicit Godot snapshot arithmetic to frozen adapted DXBC exact outputs."""
import argparse
import datetime
import json
import shutil
import subprocess
from pathlib import Path
import numpy as np
from evidence_contract import identity
from reference_budget import codes,metrics


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--rules',required=True,type=Path)
    ap.add_argument('--lowering',required=True,type=Path);ap.add_argument('--output',required=True,type=Path)
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    root=Path(__file__).resolve().parents[3];project=root/'tests/investigation/water_solver_evidence_probe'
    rules=json.loads(args.rules.read_text());parent=json.loads((args.rules.parent/'manifest.json').read_text())
    expected=next(a for a in parent['artifacts'] if a['path']==args.rules.as_posix())
    if identity(args.rules)['sha256']!=expected['sha256'] or rules['verification_status']!='passed':raise ValueError('RULES_CHANGED_OR_NOT_READY')
    lowering=json.loads((args.lowering/'lowering.json').read_text())
    for name in ['sources','inputs','raw','comparisons']:(out/name).mkdir()
    for source in [*project.glob('*.gd'),*project.glob('*.tscn'),project/'project.godot',*project.glob('shaders/*_snapshot.glsl')]:shutil.copyfile(source,out/'sources'/source.name)
    for name in ['run_snapshot_godot.py','reference_budget.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/'sources'/name)
    def checked(a):
        actual=identity(a['path'])
        if actual['sha256']!=a['sha256'] or actual['size_bytes']!=a['size_bytes']:raise ValueError('SOURCE_CHANGED')
        return a
    cases=[]
    for ref in rules['references']:
        if ref['extra_fp_allowance'] or ref['extra_quantization_allowance']:raise ValueError('RULE_NOT_EXACT')
        generated=next(p for p in lowering['programs'] if p['event']==ref['event_id'])
        if generated['execution_mode']!='snapshot':raise ValueError('NOT_SNAPSHOT_CANDIDATE')
        checked(generated['shader'])
        cases.append(dict(case_id=ref['reference_id'],event_id=ref['event_id'],execution_mode='snapshot',
            shader_path='res://shaders/'+Path(generated['shader']['path']).name,shader_sha256=generated['shader']['sha256'],
            input=checked(ref['output_seed']),snapshot=checked(ref['snapshot']),constants=checked(ref['constants']),srvs=[checked(a) for a in ref['srvs']]))
    request=dict(schema_version='1.0',execution_mode='explicit_readonly_snapshot_adaptation',repeat_count=3,output_root=(out/'raw').as_posix(),rules=identity(args.rules),lowering=identity(args.lowering/'lowering.json'),cases=cases)
    file=out/'request.json';file.write_text(json.dumps(request,indent=2),encoding='utf-8')
    godot=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe')
    command=[str(godot),'--path',str(project),'--rendering-method','mobile','--rendering-driver','vulkan','--log-file',str(out/'engine.log'),'res://kernel_probe.tscn','--','--request',str(file)]
    started=datetime.datetime.now(datetime.timezone.utc).isoformat();process=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,creationflags=subprocess.CREATE_NO_WINDOW)
    try:stdout,stderr=process.communicate(timeout=180)
    except subprocess.TimeoutExpired:process.kill();stdout,stderr=process.communicate();raise RuntimeError('OWNED_GODOT_TIMEOUT')
    (out/'stdout.bin').write_bytes(stdout);(out/'stderr.bin').write_bytes(stderr)
    result_file=out/'raw/probe_result.json';result=json.loads(result_file.read_text()) if result_file.exists() else None
    errors=[];comparisons=[]
    if process.returncode or not result or result['operation_status']!='complete':errors.append('SNAPSHOT_GODOT_RUN_FAILED')
    else:
        if len(result['cases'])!=len(cases):errors.append('CASE_COVERAGE_MISMATCH')
        for actual in result['cases']:
            ref=next(r for r in rules['references'] if r['reference_id']==actual['case_id']);checked(ref['baseline'])
            expected_codes=codes(ref['baseline']['path']);expected_words=np.fromfile(ref['baseline']['path'],dtype='<u4')
            if actual['execution_mode']!='snapshot' or actual['gpu_dependency_hashes'].get('snapshot')!=ref['snapshot']['sha256'] or actual['gpu_dependency_hashes'].get('snapshot_after')!=ref['snapshot']['sha256']:errors.append('READONLY_SNAPSHOT_PROOF_MISSING')
            for repeat in actual['repeats']:
                after=identity(repeat['after']);words=np.fromfile(repeat['after'],dtype='<u4');decoded=codes(repeat['after'])
                mismatch=int(np.count_nonzero(words!=expected_words));fields={f:metrics(decoded[f],expected_codes[f]) for f in decoded}
                comparison=dict(reference_id=ref['reference_id'],repeat=repeat['index'],candidate=after,baseline=ref['baseline'],
                    verification_status='passed' if not mismatch else 'failed',word_mismatches=mismatch,
                    first_word=int(np.flatnonzero(words!=expected_words)[0]) if mismatch else None,fields=fields,
                    scope='Exact packed bytes for matched explicit snapshot adaptation only; not original in-place')
                path=out/'comparisons'/(ref['reference_id']+'_%d.json'%repeat['index']);path.write_text(json.dumps(comparison,indent=2),encoding='utf-8');comparisons.append(dict(reference_id=ref['reference_id'],repeat=repeat['index'],status=comparison['verification_status'],report=identity(path)))
                if mismatch:errors.append(dict(reference_id=ref['reference_id'],repeat=repeat['index'],word_mismatches=mismatch))
    report=dict(operation_status='complete' if result and result['operation_status']=='complete' else 'failed',verification_status='passed' if not errors else 'failed',
        scope='Explicit snapshot arithmetic diagnostic only. Never original in-place, legal scheduling, lifecycle, sequence or G02/G5 acceptance.',
        rules=identity(args.rules),lowering=identity(args.lowering/'lowering.json'),command=command,pid=process.pid,exit_code=process.returncode,
        started_at=started,finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),godot=identity(godot),result=result,comparisons=comparisons,errors=errors)
    (out/'snapshot_comparison.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    (out/'manifest.json').write_text(json.dumps(dict(operation_status=report['operation_status'],verification_status=report['verification_status'],errors=errors,artifacts=[identity(p) for p in out.rglob('*') if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(operation=report['operation_status'],status=report['verification_status'],comparisons=len(comparisons),failed=sum(c['status']!='passed' for c in comparisons),runtime_errors=[e for e in errors if isinstance(e,str)])))
    raise SystemExit(bool(errors))


if __name__=='__main__':main()
