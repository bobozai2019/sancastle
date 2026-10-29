"""Review native E1495 bytes with instruction-derived packing, not raw preservation.

The original v1 failed verifier is retained. This audits its existing evidence,
without rerunning the same GPU experiment or modifying a tolerance.
"""
import argparse
import json
import shutil
from pathlib import Path
import numpy as np
from evidence_contract import identity
from analyze_repeats import difference


def expected_repacked_words(a):
    code_x=(a[:,0]>>16)|((a[:,1]&255)<<16)
    code_z=a[:,1]>>8
    code_bed=(a[:,2]>>24)|((a[:,3]&65535)<<8)
    def repack(codes):return (codes.astype(np.float32)+np.float32(0.5)).astype(np.uint32)
    x,z,bed=[repack(c) for c in [code_x,code_z,code_bed]]
    return (a[:,0]&65535)|(x<<16),(z<<8)|(x>>16),bed


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-run',required=True,type=Path)
    parser.add_argument('--hex-assembly',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args();out=args.output
    if not out.is_absolute() or not str(out).isascii():raise ValueError('Absolute ASCII output required')
    out.mkdir(parents=True,exist_ok=False)
    for name in ['sources','raw','derived','logs']:(out/name).mkdir()
    run=args.input_run
    manifest=json.loads((run/'manifest.json').read_text());errors=[]
    file_checks=[]
    for artifact in manifest['artifacts']:
        actual=identity(artifact['path']);matched=actual['sha256']==artifact['sha256'] and actual['size_bytes']==artifact['size_bytes']
        file_checks.append(dict(path=artifact['path'],matched=matched))
        if not matched:errors.append('ARTIFACT_CHANGED:'+artifact['path'])
    if manifest['operation_status']!='complete':errors.append('ORIGINAL_EXECUTION_INCOMPLETE')
    a=np.fromfile(run/'sources/input.bin',dtype='<u4').reshape(-1,4)
    code_x=(a[:,0]>>16)|((a[:,1]&255)<<16);code_z=a[:,1]>>8
    code_bed=(a[:,2]>>24)|((a[:,3]&65535)<<8)
    def repack(codes):return (codes.astype(np.float32)+np.float32(0.5)).astype(np.uint32)
    x,z,bed=[repack(c) for c in [code_x,code_z,code_bed]]
    expect0,expect1,bed=expected_repacked_words(a)
    checks=[];metrics=[]
    logs=[json.loads(line) for line in (run/'raw/execution.jsonl').read_text().splitlines()]
    seed=identity(run/'sources/input.bin')
    for index,log in enumerate(logs):
        before=run/('raw/before_%d.bin'%index);after=run/('raw/after_%d.bin'%index)
        b=np.fromfile(after,dtype='<u4').reshape(-1,4)
        mismatches=[int(np.count_nonzero(b[:,0]!=expect0)),int(np.count_nonzero(b[:,1]!=expect1)),
                    int(np.count_nonzero((b[:,2]&0xff000000)!=(bed<<24))),
                    int(np.count_nonzero((b[:,3]&0xffff)!=(bed>>8))),
                    int(np.count_nonzero((b[:,3]&0xff000000)!=(a[:,3]&0xff000000)))]
        restored=identity(before)['sha256']==seed['sha256'];completed=log['fence_completed']>=log['fence_ticket']
        if any(mismatches):errors.append('PACKING_MISMATCH:repeat%d'%index)
        if not restored or not completed:errors.append('RESTORATION_OR_COMPLETION_FAILED:repeat%d'%index)
        checks.append(dict(repeat=index,restored=restored,fence_complete=completed,instruction_packing_mismatches=mismatches,
                           before=identity(before),after=identity(after),
                           original_verifier_failure='Incorrect assumption that velocity uint words are bit-preserved'))
    if len(logs)<3:errors.append('TOO_FEW_REPEATS')
    for left in range(len(logs)):
        for right in range(left+1,len(logs)):
            metrics.append(dict(left=left,right=right,controlled_same_input=True,
                output_difference=difference(run/('raw/after_%d.bin'%left),run/('raw/after_%d.bin'%right))))
    packing=dict(program_sha256=identity(run/'sources/program.dxbc')['sha256'],
        formula='uint(float32(code24) + float32(0.5))',
        observed_code_changes=dict(vx=int(np.count_nonzero(x!=code_x)),vz=int(np.count_nonzero(z!=code_z)),bed=int(np.count_nonzero(bed!=code_bed))),
        evidence='E1495 DXBC instructions 64-90 and 101-120; /Lx hex constants 0x3f800000 and 0x3f000000. Float code is rounded directly before integer conversion, not only new A.',
        consequence='For odd codes above 2^23, +0.5 rounds to the neighboring even binary32 integer. This changes a pass-through field by one code.',
        scope='Observed seed; maximum code overflow and additional kernels require controlled threshold cases',
        candidate_implementation=False, numeric_budget=None)
    for filename,data in [('packing.json',packing),('checks.json',checks),('metrics.json',metrics),('file_checks.json',file_checks)]:
        (out/'derived'/filename).write_text(json.dumps(data,indent=2),encoding='utf-8')
    for path in [Path(__file__),Path(__file__).with_name('evidence_contract.py'),Path(__file__).with_name('analyze_repeats.py'),args.hex_assembly]:
        shutil.copyfile(path,out/'sources'/path.name)
    fxc=Path('C:/Program Files (x86)/Windows Kits/10/bin/10.0.26100.0/x64/fxc.exe')
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status='passed' if not errors else 'failed',
        source_manifest=identity(run/'manifest.json'),errors=errors,pairing_kind='reconstructed_controlled' if not errors else 'unproven',
        scope='Reanalysis of original same-input E1495 pilot; not G3 six-kernel coverage or an error budget',
        packing_assembly=identity(args.hex_assembly),fxc=identity(fxc),
        fxc_command=[str(fxc),'/dumpbin','/Lx','/Fc',str(args.hex_assembly),json.loads((run/'request.json').read_text())['program']['path']],
        artifacts=[identity(p) for p in out.rglob('*') if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(errors=errors,packing=packing['observed_code_changes'],
                         changed_cells=[m['output_difference']['changed_cells'] for m in metrics])))
    raise SystemExit(1 if errors else 0)


if __name__=='__main__':main()
