"""Build the isolated original-DXBC reference with the installed MSVC/SDK."""
import argparse
import json
import subprocess
from pathlib import Path
from evidence_contract import identity


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--vcvars',type=Path,default=Path('D:/IDE_SOFTWARE/vs/VC/Auxiliary/Build/vcvars64.bat'))
    args=parser.parse_args();out=args.output
    if not out.is_absolute() or not str(out).isascii():raise ValueError('Absolute ASCII path required')
    out.mkdir(parents=True,exist_ok=False)
    source=Path(__file__).with_name('native_reference')/'water_reference.cpp'
    (out/'water_reference.cpp').write_bytes(source.read_bytes())
    batch=out/'build.cmd'
    batch.write_text('@echo off\ncall "'+str(args.vcvars)+'"\nif errorlevel 1 exit /b %errorlevel%\nwhere cl\nwhere link\ncl /Bv /nologo /std:c++17 /EHsc /O2 /W4 "'+str(out/'water_reference.cpp')+'" /Fe:"'+str(out/'water_reference.exe')+'" /Fo:"'+str(out/'water_reference.obj')+'" /link d3d12.lib dxgi.lib d3dcompiler.lib dxguid.lib\nexit /b %errorlevel%\n',encoding='ascii')
    result=subprocess.run(['cmd.exe','/d','/c',str(batch)],cwd=out,capture_output=True)
    (out/'build_stdout.bin').write_bytes(result.stdout);(out/'build_stderr.bin').write_bytes(result.stderr)
    manifest=dict(operation_status='complete' if result.returncode==0 else 'failed',verification_status='not_evaluated',
        exit_code=result.returncode,source=identity(source),vcvars=identity(args.vcvars),
        artifacts=[identity(p) for p in out.iterdir() if p.is_file()])
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print(result.stdout.decode('utf-8',errors='replace'));print(result.stderr.decode('utf-8',errors='replace'))
    print(json.dumps(dict(exit_code=result.returncode,output=out.as_posix())))
    raise SystemExit(result.returncode)


if __name__=='__main__':main()
