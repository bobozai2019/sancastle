"""Build six-kernel original-alias capture / fixed-stream replay executor."""
import argparse
import json
import shutil
import subprocess
from pathlib import Path
from evidence_contract import identity


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',required=True,type=Path);args=ap.parse_args()
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=False);here=Path(__file__).parent
    source=here/'native_trace_reference/water_trace_reference.cpp';text=source.read_text();parent=identity(source);patches=[]
    def patch(old,new):
        nonlocal text
        if text.count(old)!=1:raise ValueError('PATCH_ANCHOR:'+old)
        text=text.replace(old,new);patches.append(dict(original=old,replacement=new))
    patch('"--output", "--snapshot"','"--output"')
    patch('"--texture0","--snapshot"','"--texture0","--stream-input"')
    patch('constexpr size_t waterBytes=512*256*16;','constexpr size_t waterBytes=512*256*16;\n        const UINT readCount=(kind=="floor" || kind=="sources")?1:5;\n        const size_t streamBytes=waterBytes*readCount*2;\n        bool replay=args.count("--stream-input")!=0;')
    patch('UINT expectedSrv=(kind=="floor"?1:kind=="sources"?2:0)+1;','UINT expectedSrv=(kind=="floor"?1:kind=="sources"?2:0)+(replay?1:0);')
    start=text.index('        if(declarationCount(std::regex("dcl_resource_structured t2, 16"))')
    end=text.index('        if(kind=="floor"',start)
    old=text[start:end]
    new=r'''        const UINT waterLoads=declarationCount(std::regex(R"(ld_structured_indexable[^\r\n]* u0\.)"));
        const UINT streamLoads=declarationCount(std::regex(R"(ld_structured_indexable[^\r\n]* t2\.)"));
        if(replay){
            if(declarationCount(std::regex("dcl_resource_structured t2, 16"))!=1 || waterLoads!=0 || streamLoads!=readCount)
                throw std::runtime_error("NOT_DECLARED_READ_STREAM_REPLAY");
        }else if(waterLoads!=readCount || streamLoads!=0)throw std::runtime_error("NOT_DECLARED_ORIGINAL_ALIAS_CAPTURE");
'''
    patch(old,new)
    patch('srvBytes[2]=read(args["--snapshot"]);\n        if(srvBytes[2].size()!=waterBytes)throw std::runtime_error("DEPENDENCY_SIZE_MISMATCH:snapshot_t2");',
          'if(replay){srvBytes[2]=read(args["--stream-input"]);\n        if(srvBytes[2].size()!=streamBytes)throw std::runtime_error("DEPENDENCY_SIZE_MISMATCH:stream_t2");}')
    for name in ['debug','debugSeed','debugReadback']:
        patch('auto '+name+'=buffer(device.Get(),waterBytes,','auto '+name+'=buffer(device.Get(),streamBytes,')
    patch('upload(debugSeed.Get(),std::vector<char>(waterBytes,0),waterBytes);','upload(debugSeed.Get(),std::vector<char>(streamBytes,0),streamBytes);')
    patch('device->CreateUnorderedAccessView(debug.Get(),nullptr,&view,debugLocation);',
          'auto streamView=view;streamView.Buffer.NumElements=static_cast<UINT>(streamBytes/16);\n        device->CreateUnorderedAccessView(debug.Get(),nullptr,&streamView,debugLocation);')
    patch('list->CopyBufferRegion(debug.Get(),0,debugSeed.Get(),0,waterBytes);','list->CopyBufferRegion(debug.Get(),0,debugSeed.Get(),0,streamBytes);')
    patch('D3D12_RANGE reads={0,waterBytes};check(debugReadback->Map','D3D12_RANGE reads={0,streamBytes};check(debugReadback->Map')
    patch('write(output/("trace_"+std::to_string(repeat)+".bin"),ptr,waterBytes);','write(output/("stream_"+std::to_string(repeat)+".bin"),ptr,streamBytes);')
    patch('explicit readonly snapshot t2 source, separate u0 output','u0 alias capture or explicit post-swizzle stream t2 replay; u1 readstream records')
    text=text.replace('explicit_snapshot_adaptation','explicit_readstream_adaptation').replace('register_observation_uav','readstream_output_uav')
    text=text.replace('// Explicit frozen-read snapshot adaptation. Edited DXBC is never an original in-place reference.',
                      '// Instrumented original UAV alias capture / fixed read-stream adaptation. Never unmodified original execution.')
    text=text.replace('water_trace_reference --snapshot <uint4 readonly input>','water_readstream_reference [--stream-input <4MiB floor/sources or 20MiB simple replay records>]')
    target=here/'native_readstream_reference/water_readstream_reference.cpp';target.parent.mkdir(exist_ok=True);target.write_text(text,encoding='utf-8');shutil.copyfile(target,out/target.name)
    (out/'patches.json').write_text(json.dumps(dict(parent=parent,source=identity(target),patches=patches,scope='Six frozen water kernels; original sand/texture/air SRVs preserved, u1 stores one or five ordered read pairs per invocation'),indent=2),encoding='utf-8')
    vcvars=Path('D:/IDE_SOFTWARE/vs/VC/Auxiliary/Build/vcvars64.bat');batch=out/'build.cmd';exe=out/'water_readstream_reference.exe'
    batch.write_text('@echo off\ncall "'+str(vcvars)+'"\nif errorlevel 1 exit /b %errorlevel%\ncl /Bv /nologo /std:c++17 /EHsc /O2 /W4 "'+str(out/target.name)+'" /Fe:"'+str(exe)+'" /Fo:"'+str(out/'water_readstream_reference.obj')+'" /link d3d12.lib dxgi.lib d3dcompiler.lib dxguid.lib\nexit /b %errorlevel%\n',encoding='ascii')
    result=subprocess.run(['cmd.exe','/d','/c',str(batch)],cwd=out,capture_output=True);(out/'stdout.bin').write_bytes(result.stdout);(out/'stderr.bin').write_bytes(result.stderr)
    for name in ['build_readstream_reference.py','evidence_contract.py']:shutil.copyfile(here/name,out/name)
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete' if not result.returncode else 'failed',verification_status='not_evaluated',exit_code=result.returncode,parent=parent,scope='Build only; no GPU/reference acceptance',artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(exit_code=result.returncode)));raise SystemExit(result.returncode)


if __name__=='__main__':main()
