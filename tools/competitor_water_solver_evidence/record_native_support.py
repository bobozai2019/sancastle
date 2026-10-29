"""Preserve native pilot build/disassembly provenance and actual input negatives."""
import argparse
import json
import shutil
import subprocess
from pathlib import Path
from evidence_contract import identity


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--build',type=Path,required=True);p.add_argument('--pilot',type=Path,required=True)
    p.add_argument('--assembly',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();out=args.output
    if not out.is_absolute() or not str(out).isascii():raise ValueError('Absolute ASCII output required')
    out.mkdir(parents=True,exist_ok=False)
    for name in ['raw','sources','derived','logs']:(out/name).mkdir()
    for name in ['build.cmd','build_stdout.bin','build_stderr.bin','manifest.json']:
        shutil.copyfile(args.build/name,out/'sources'/('build_'+name))
    shutil.copyfile(args.assembly,out/'derived/e1495_hex.asm')
    for name in ['record_native_support.py','evidence_contract.py']:
        shutil.copyfile(Path(__file__).with_name(name),out/'sources'/name)
    req=json.loads((args.pilot/'request.json').read_text())
    (out/'raw/truncated_water.bin').write_bytes(b'1234')
    (out/'raw/not_a_program.dxbc').write_bytes(b'NEGATIVE_FIXTURE!')
    cases=[('truncated_input',args.pilot/'sources/program.dxbc',out/'raw/truncated_water.bin','DEPENDENCY_SIZE_MISMATCH'),
           ('wrong_program_header',out/'raw/not_a_program.dxbc',args.pilot/'sources/input.bin','EXPECTED_ORIGINAL_DXBC')]
    results=[]
    for name,program,seed,expected in cases:
        target=out/('rejected_'+name)
        command=[str(args.pilot/'sources/water_reference.exe'),'--program',str(program),'--input',str(seed),
                 '--constants',str(args.pilot/'sources/constants.bin'),'--output',str(target),'--repeat','3']
        result=subprocess.run(command,capture_output=True,text=True)
        (out/'logs'/(name+'.txt')).write_text(result.stdout+result.stderr,encoding='utf-8')
        results.append(dict(name=name,command=command,exit_code=result.returncode,expected=expected,
            rejected_before_output_creation=not target.exists(),passed=result.returncode!=0 and expected in result.stderr and not target.exists()))
    (out/'derived/negative_checks.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
    fxc=Path('C:/Program Files (x86)/Windows Kits/10/bin/10.0.26100.0/x64/fxc.exe')
    provenance=dict(source_program=identity(req['program']['path']),assembly=identity(args.assembly),fxc=identity(fxc),
        actual_fxc_command=[str(fxc),'/dumpbin','/Lx','/Fc',str(args.assembly),req['program']['path']],
        native_build=identity(args.build/'manifest.json'),native_pilot=identity(args.pilot/'manifest.json'),
        build_limitation='First build records vcvars, source and binary hashes; exact compiler path/version was not printed. Expanded build will emit where cl/link and /Bv.',
        timing='No performance claim; runtime completion proved by per-dispatch fence/readback evidence')
    (out/'derived/provenance.json').write_text(json.dumps(provenance,indent=2),encoding='utf-8')
    errors=[] if all(r['passed'] for r in results) else ['NEGATIVE_CHECK_FAILED']
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status='failed' if errors else 'passed',errors=errors,
        artifacts=[identity(f) for f in out.rglob('*') if f.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(errors=errors,negatives=results)))
    raise SystemExit(1 if errors else 0)


if __name__=='__main__':main()
