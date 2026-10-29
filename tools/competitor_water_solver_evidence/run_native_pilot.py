"""Run and audit a controlled E1495 original-DXBC compatibility pilot."""
import argparse
import datetime
import json
import shutil
import subprocess
from pathlib import Path
import numpy as np
from evidence_contract import identity
from analyze_repeats import difference
from audit_native_pilot import expected_repacked_words


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--replay-manifest',type=Path,required=True)
    parser.add_argument('--executable',type=Path,required=True)
    parser.add_argument('--input',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--repeat',type=int,default=3)
    args=parser.parse_args();out=args.output
    if not out.is_absolute() or not str(out).isascii():raise ValueError('Absolute ASCII output required')
    m=json.loads(args.replay_manifest.read_text())
    row=next(e for e in m['events'] if e['event_id']==1495)
    program=Path(row['program']['path']);constants=Path(row['constants'][0]['raw']['path'])
    if identity(program)['sha256']!='549114c23f1921610bacaf1d9ae375814fda1fb1de492cc2a4acfc53a502c64f':raise ValueError('SELECTOR_MISMATCH:program')
    if identity(constants)['sha256']!=row['constants'][0]['raw']['sha256']:raise ValueError('SOURCE_CHANGED:constants')
    if identity(args.input)['size_bytes']!=2097152:raise ValueError('DEPENDENCY_MISSING:input')
    out.mkdir(parents=True,exist_ok=False)
    for name in ['sources','logs','derived']:(out/name).mkdir()
    for path,name in [(program,'program.dxbc'),(constants,'constants.bin'),(args.input,'input.bin'),(args.executable,'water_reference.exe')]:
        shutil.copyfile(path,out/'sources'/name)
    for name in ['run_native_pilot.py','evidence_contract.py','analyze_repeats.py','audit_native_pilot.py']:
        shutil.copyfile(Path(__file__).with_name(name),out/'sources'/name)
    source_cpp=Path(__file__).with_name('native_reference')/'water_reference.cpp'
    shutil.copyfile(source_cpp,out/'sources/water_reference.cpp')
    command=[str(out/'sources/water_reference.exe'),'--program',str(out/'sources/program.dxbc'),'--input',str(out/'sources/input.bin'),
        '--constants',str(out/'sources/constants.bin'),'--output',str(out/'raw'),'--repeat',str(args.repeat)]
    request=dict(command=command,program=identity(program),input=identity(args.input),constants=identity(constants),
                 executable=identity(args.executable),original_replay_manifest=identity(args.replay_manifest),
                 pairing_kind='reconstructed_controlled',input_origin='Frozen post-E1490 derivative used as controlled fixture, not claimed original E1495 pre-state',
                 scope='E1495 compatibility and controlled same-input repetitions only',
                 perturbation='Copy restored water into independent readback before dispatch, plus transitions, output copy and queue fence wait',
                 frozen_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),numeric_budget=None)
    (out/'request.json').write_text(json.dumps(request,indent=2),encoding='utf-8')
    result=subprocess.run(command,capture_output=True,text=True)
    (out/'logs/stdout.txt').write_text(result.stdout,encoding='utf-8');(out/'logs/stderr.txt').write_text(result.stderr,encoding='utf-8')
    errors=[];checks=[];metrics=[]
    if result.returncode:errors.append(dict(code='NATIVE_EXECUTION_FAILED',message=result.stderr))
    else:
        input_data=np.fromfile(out/'sources/input.bin',dtype='<u4').reshape(-1,4)
        expect0,expect1,bed=expected_repacked_words(input_data)
        logs=[json.loads(line) for line in (out/'raw/execution.jsonl').read_text().splitlines()]
        for index in range(args.repeat):
            before=out/('raw/before_%d.bin'%index);after=out/('raw/after_%d.bin'%index)
            restored=identity(before)['sha256']==request['input']['sha256']
            if not restored:errors.append(dict(code='INPUT_NOT_RESTORED',repeat=index))
            data=np.fromfile(after,dtype='<u4').reshape(-1,4)
            preserved=[int(np.count_nonzero(data[:,0]!=expect0)),int(np.count_nonzero(data[:,1]!=expect1)),
                int(np.count_nonzero((data[:,2]&0xff000000)!=(bed<<24))),
                int(np.count_nonzero((data[:,3]&0xffff)!=(bed>>8))),
                int(np.count_nonzero((data[:,3]&0xff000000)!=(input_data[:,3]&0xff000000)))]
            if any(preserved):errors.append(dict(code='PRESERVED_BITS_CHANGED',repeat=index,mismatches=preserved))
            complete=logs[index]['fence_completed']>=logs[index]['fence_ticket']
            if not complete:errors.append(dict(code='GPU_NOT_COMPLETE',repeat=index))
            checks.append(dict(repeat=index,before=identity(before),after=identity(after),restored=restored,
                               fence_complete=complete,preserved_bit_mismatches=preserved))
            metrics.append(dict(repeat=index,input_to_output=difference(out/'sources/input.bin',after)))
        for left in range(args.repeat):
            for right in range(left+1,args.repeat):
                metrics.append(dict(left=left,right=right,controlled_same_input=True,
                    output_difference=difference(out/('raw/after_%d.bin'%left),out/('raw/after_%d.bin'%right))))
    (out/'derived/checks.json').write_text(json.dumps(checks,indent=2),encoding='utf-8')
    (out/'derived/metrics.json').write_text(json.dumps(metrics,indent=2),encoding='utf-8')
    manifest=dict(operation_status='complete' if result.returncode==0 else 'failed',verification_status='passed' if not errors else 'failed',
        scope='Compatibility and controlled restoration pilot only. Six-kernel reference coverage, observation perturbation comparison and error budgets still pending.',
        pairing_kind='reconstructed_controlled' if not errors else 'unproven',exit_code=result.returncode,errors=errors,
        request=identity(out/'request.json'),artifacts=[identity(p) for p in out.rglob('*') if p.is_file()])
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print(json.dumps(dict(output=out.as_posix(),errors=errors,exit_code=result.returncode)))
    raise SystemExit(1 if errors else 0)


if __name__=='__main__':main()
