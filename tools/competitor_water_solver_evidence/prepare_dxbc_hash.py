"""Build Microsoft's public container hash helper and validate all six original stored digests."""
import argparse
import ctypes
import datetime
import json
import shutil
import subprocess
import urllib.request
from pathlib import Path
from evidence_contract import identity


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',required=True,type=Path)
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    if not str(out).isascii():raise ValueError('ASCII output required')
    base=out.parent
    request=urllib.request.Request('https://api.github.com/repos/microsoft/DirectXShaderCompiler/commits/main',headers={'User-Agent':'sandcastle-water-evidence'})
    metadata=json.loads(urllib.request.urlopen(request,timeout=30).read());commit=metadata['sha']
    (out/'upstream_commit.json').write_text(json.dumps(metadata,indent=2),encoding='utf-8')
    upstream=[]
    for remote,local in [('lib/DxilHash/DxilHash.cpp','DxilHash.cpp'),('LICENSE.TXT','LICENSE.TXT')]:
        url='https://raw.githubusercontent.com/microsoft/DirectXShaderCompiler/'+commit+'/'+remote
        data=urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'sandcastle-water-evidence'}),timeout=30).read()
        (out/local).write_bytes(data);upstream.append(dict(url=url,commit=commit,artifact=identity(out/local)))
    wrapper=out/'container_hash.cpp'
    wrapper.write_text('#include "DxilHash.cpp"\nextern "C" __declspec(dllexport) void container_hash(const unsigned char* p,unsigned int n,unsigned char* out){ComputeHashRetail(p,n,out);}\n',encoding='ascii')
    batch=out/'build.cmd'
    batch.write_text('@echo off\ncall "D:\\IDE_SOFTWARE\\vs\\VC\\Auxiliary\\Build\\vcvars64.bat"\nif errorlevel 1 exit /b %errorlevel%\ncl /Bv /nologo /EHsc /std:c++17 /O2 /DNDEBUG /LD "'+str(wrapper)+'" /Fo:"'+str(out/'container_hash.obj')+'" /link /OUT:"'+str(out/'container_hash.dll')+'"\nexit /b %errorlevel%\n',encoding='ascii')
    result=subprocess.run(['cmd.exe','/d','/c',str(batch)],cwd=out,capture_output=True)
    (out/'build_stdout.bin').write_bytes(result.stdout);(out/'build_stderr.bin').write_bytes(result.stderr)
    if result.returncode:raise RuntimeError('Hash helper build failed; logs retained')
    dll=ctypes.CDLL(str(out/'container_hash.dll'));fn=dll.container_hash
    fn.argtypes=[ctypes.c_void_p,ctypes.c_uint,ctypes.c_void_p];fn.restype=None
    checks=[]
    for event in [1484,1490,1495,1500,1537,1543]:
        file=base/'t06_exact_programs_20261025_v1'/('e%d.dxbc'%event);data=file.read_bytes();buf=ctypes.create_string_buffer(data[20:]);digest=ctypes.create_string_buffer(16)
        fn(buf,len(data)-20,digest);checks.append(dict(source=identity(file),stored=data[4:20].hex(),computed=digest.raw.hex(),equal=digest.raw==data[4:20]))
    for name in ['prepare_dxbc_hash.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/name)
    report=dict(operation_status='complete',verification_status='passed' if all(c['equal'] for c in checks) else 'failed',
        scope='Public container checksum implementation validated on original blobs, CPU only. Not instruction semantics, GPU pipeline or numerical equivalence.',
        downloaded_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),upstream=upstream,build_exit=result.returncode,
        helper=identity(out/'container_hash.dll'),checks=checks)
    (out/'hash_probe.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status=report['verification_status'],artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(status=report['verification_status'],commit=commit,checks=len(checks))))
    raise SystemExit(report['verification_status']!='passed')


if __name__=='__main__':main()
