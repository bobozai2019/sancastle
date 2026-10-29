"""GPU compatibility for explicitly edited container copies, never original-program certification."""
import argparse
import datetime
import json
import shutil
import subprocess
from pathlib import Path
from evidence_contract import identity


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--rebuild',required=True,type=Path);ap.add_argument('--output',required=True,type=Path)
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    base=out.parent;source=base/'t03_six_kernel_20261025_v4'
    rebuilt=json.loads((args.rebuild/'probe.json').read_text())
    if rebuilt['verification_status']!='passed':raise ValueError('CPU_COMPATIBILITY_NOT_PASSED')
    for name in ['sources','raw','logs']:(out/name).mkdir()
    exe=out/'sources/water_reference.exe';shutil.copyfile(source/'sources/water_reference.exe',exe)
    original=json.loads((source/'manifest.json').read_text());expected=next(a for a in original['artifacts'] if a['path']==(source/'sources/water_reference.exe').as_posix())
    if identity(exe)['sha256']!=expected['sha256']:raise ValueError('EXECUTOR_CHANGED')
    floor=source/'sources/e1484'
    inputs={name:identity(floor/file) for name,file in [('input','water.bin'),('constants','constants.bin'),('srv0','srv0.bin')]}
    (out/'request.json').write_text(json.dumps(dict(operation='adapted_container_compatibility_only',cases=rebuilt['cases'],inputs=inputs,repeat_count=3,
        label='Metadata and checksum changes plus one duplicated register-only MOV; no claim of unmodified original DXBC for these blobs',frozen_before_execution=datetime.datetime.now(datetime.timezone.utc).isoformat()),indent=2),encoding='utf-8')
    rows=[];errors=[]
    for case in rebuilt['cases']:
        program=case['output'];actual=identity(program['path'])
        if actual['sha256']!=program['sha256']:raise ValueError('EDITED_PROGRAM_CHANGED')
        target=out/'raw'/case['case']
        command=[str(exe),'--program',program['path'],'--input',inputs['input']['path'],'--constants',inputs['constants']['path'],'--srv0',inputs['srv0']['path'],'--kind','floor','--before-copy','1','--repeat','3','--output',str(target)]
        result=subprocess.run(command,capture_output=True,timeout=60,creationflags=subprocess.CREATE_NO_WINDOW)
        (out/'logs'/(case['case']+'.stdout.bin')).write_bytes(result.stdout);(out/'logs'/(case['case']+'.stderr.bin')).write_bytes(result.stderr)
        checks=[]
        if result.returncode==0:
            execution=[json.loads(s) for s in (target/'execution.jsonl').read_text().splitlines()]
            for index,e in enumerate(execution):
                before=identity(target/('before_%d.bin'%index));sand=identity(target/('srv0_before_%d.bin'%index));after=identity(target/('after_%d.bin'%index))
                passed=e['fence_completed']>=e['fence_ticket'] and before['sha256']==inputs['input']['sha256'] and sand['sha256']==inputs['srv0']['sha256'] and after['sha256']==inputs['input']['sha256']
                checks.append(dict(repeat=index,before=before,sand_before=sand,after=after,fence=e,exact_expected_floor_output=passed))
                if not passed:errors.append(case['case']+':OUTPUT_OR_INPUT_MISMATCH')
            if len(execution)!=3:errors.append('EXECUTION_COUNT_MISMATCH')
        else:errors.append(case['case']+':PIPELINE_OR_EXECUTION_REJECTED')
        rows.append(dict(case=case['case'],adapted_program=program,command=command,exit_code=result.returncode,checks=checks))
    for name in ['probe_dxbc_rebuild_gpu.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/'sources'/name)
    report=dict(operation_status='complete',verification_status='passed' if not errors else 'failed',
        scope='Explicit container-edit GPU compatibility and one idempotent floor control only. Not a trace replay oracle, original-program equivalence, six kernels or G5.',
        rebuild=identity(args.rebuild/'probe.json'),executor=expected,cases=rows,errors=errors)
    (out/'probe.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status=report['verification_status'],errors=errors,artifacts=[identity(p) for p in out.rglob('*') if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(status=report['verification_status'],cases=len(rows),errors=errors)))
    raise SystemExit(bool(errors))


if __name__=='__main__':main()
