"""Build a separately labelled snapshot-adaptation executor, leaving the original reference intact."""
import argparse
import json
import shutil
import subprocess
from pathlib import Path
from evidence_contract import identity


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',required=True,type=Path)
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    here=Path(__file__).parent;source=here/'native_reference/water_reference.cpp';text=source.read_text()
    original=identity(source);patches=[]
    def patch(old,new):
        nonlocal text
        count=text.count(old)
        if count!=1:raise ValueError('PATCH_ANCHOR_COUNT:'+str(count)+':'+old[:80])
        text=text.replace(old,new);patches.append(dict(original=old,replacement=new))
    patch('// Controlled original-DXBC water kernels. No shader recompilation or game code.',
          '// Explicit frozen-read snapshot adaptation. Edited DXBC is never an original in-place reference.')
    patch('for (auto key : {"--program", "--input", "--constants", "--output"})',
          'for (auto key : {"--program", "--input", "--constants", "--output", "--snapshot"})')
    patch('"--before-copy","--srv0","--srv1","--texture0"}',
          '"--before-copy","--srv0","--srv1","--texture0","--snapshot"}')
    patch('else if(binding.Type==D3D_SIT_STRUCTURED && ((kind=="floor" && binding.BindPoint==0) || (kind=="sources" && binding.BindPoint==1)))++srvCount;',
          'else if(binding.Type==D3D_SIT_STRUCTURED && ((kind=="floor" && binding.BindPoint==0) || (kind=="sources" && binding.BindPoint==1) || binding.BindPoint==2))++srvCount;')
    patch('UINT expectedSrv=kind=="floor"?1:kind=="sources"?2:0;',
          'UINT expectedSrv=(kind=="floor"?1:kind=="sources"?2:0)+1;\n        constexpr UINT srvSpan=3;')
    anchor='if(declaredSrvs!=expectedSrv)throw std::runtime_error("SELECTOR_MISMATCH:resource_declaration_count");'
    patch(anchor,anchor+r'''
        if(declarationCount(std::regex("dcl_resource_structured t2, 16"))!=1 ||
           declarationCount(std::regex("ld_structured_indexable[^\\r\\n]* u0\\."))!=0 ||
           declarationCount(std::regex("ld_structured_indexable[^\\r\\n]* t2\\."))==0)
            throw std::runtime_error("NOT_EXPLICIT_SNAPSHOT_READ_LAYOUT");'''.replace('\\"','"'))
    patch('std::map<UINT,std::vector<char>> srvBytes;',
          'std::map<UINT,std::vector<char>> srvBytes;\n        srvBytes[2]=read(args["--snapshot"]);\n        if(srvBytes[2].size()!=waterBytes)throw std::runtime_error("DEPENDENCY_SIZE_MISMATCH:snapshot_t2");')
    patch('srvRange.NumDescriptors=expectedSrv;srvRange.BaseShaderRegister=0;',
          'srvRange.NumDescriptors=srvSpan;srvRange.BaseShaderRegister=0;')
    patch('hd.NumDescriptors=1+expectedSrv;', 'hd.NumDescriptors=1+srvSpan;')
    patch('std::vector<SrvInput> srvInputs;',r'''// Null descriptors only fill undeclared holes; every declared SRV has real bytes.
        for(UINT slot=0;slot<srvSpan;++slot)if(!srvBytes.count(slot)){
            D3D12_SHADER_RESOURCE_VIEW_DESC nullView={};nullView.Shader4ComponentMapping=D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
            nullView.ViewDimension=D3D12_SRV_DIMENSION_BUFFER;nullView.Format=DXGI_FORMAT_UNKNOWN;
            nullView.Buffer.NumElements=1;nullView.Buffer.StructureByteStride=16;
            auto location=heap->GetCPUDescriptorHandleForHeapStart();location.ptr+=static_cast<SIZE_T>(1+slot)*descriptorIncrement;
            device->CreateShaderResourceView(nullptr,&nullView,location);
        }
        std::vector<SrvInput> srvInputs;''')
    text=text.replace('same resource read/write','explicit readonly snapshot t2 source, separate u0 output')
    text=text.replace('EXPECTED_ORIGINAL_DXBC','EXPECTED_EXPLICIT_ADAPTED_DXBC').replace('ReflectOriginalDXBC','ReflectAdaptedDXBC').replace('CreateOriginalDXBCPipeline','CreateAdaptedDXBCPipeline').replace('original_program.asm','adapted_program.asm')
    text=text.replace('water_reference --program','water_snapshot_reference --snapshot <uint4 readonly input> --program')
    patch(r'\"dxbc_unmodified\":true',r'\"dxbc_unmodified\":false,\"explicit_snapshot_adaptation\":true')
    destination=here/'native_snapshot_reference/water_snapshot_reference.cpp';destination.parent.mkdir(exist_ok=True)
    destination.write_text(text,encoding='utf-8');shutil.copyfile(destination,out/'water_snapshot_reference.cpp')
    (out/'patches.json').write_text(json.dumps(dict(parent_source=original,derived_source=identity(destination),patches=patches,scope='Executor adaptation for explicit t2 snapshot only'),indent=2),encoding='utf-8')
    vcvars=Path('D:/IDE_SOFTWARE/vs/VC/Auxiliary/Build/vcvars64.bat');batch=out/'build.cmd';exe=out/'water_snapshot_reference.exe'
    batch.write_text('@echo off\ncall "'+str(vcvars)+'"\nif errorlevel 1 exit /b %errorlevel%\ncl /Bv /nologo /std:c++17 /EHsc /O2 /W4 "'+str(out/'water_snapshot_reference.cpp')+'" /Fe:"'+str(exe)+'" /Fo:"'+str(out/'water_snapshot_reference.obj')+'" /link d3d12.lib dxgi.lib d3dcompiler.lib dxguid.lib\nexit /b %errorlevel%\n',encoding='ascii')
    result=subprocess.run(['cmd.exe','/d','/c',str(batch)],cwd=out,capture_output=True)
    (out/'stdout.bin').write_bytes(result.stdout);(out/'stderr.bin').write_bytes(result.stderr)
    for name in ['build_snapshot_reference.py','evidence_contract.py']:shutil.copyfile(here/name,out/name)
    report=dict(operation_status='complete' if not result.returncode else 'failed',verification_status='not_evaluated',exit_code=result.returncode,
        scope='Explicit snapshot-adaptation executable build only, no GPU compatibility or numeric acceptance',parent_source=original,source=identity(destination),vcvars=identity(vcvars),
        artifacts=[identity(p) for p in out.iterdir() if p.is_file()])
    (out/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(dict(exit_code=result.returncode,output=out.as_posix())))
    raise SystemExit(result.returncode)


if __name__=='__main__':main()
