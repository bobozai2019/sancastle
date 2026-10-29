"""Build explicit snapshot plus independent register-observation UAV executor."""
import argparse
import json
import shutil
import subprocess
from pathlib import Path
from evidence_contract import identity


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',required=True,type=Path);args=ap.parse_args()
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=False);here=Path(__file__).parent
    source=here/'native_snapshot_reference/water_snapshot_reference.cpp';text=source.read_text();parent=identity(source);patches=[]
    def patch(old,new):
        nonlocal text
        if text.count(old)!=1:raise ValueError('PATCH_ANCHOR:'+old)
        text=text.replace(old,new);patches.append(dict(original=old,replacement=new))
    patch('binding.Type==D3D_SIT_UAV_RWSTRUCTURED && binding.BindPoint==0','binding.Type==D3D_SIT_UAV_RWSTRUCTURED && binding.BindPoint<=1')
    patch('uavCount!=1','uavCount!=2')
    patch('declarationCount(std::regex("dcl_uav_"))!=1 || declarationCount(std::regex("dcl_uav_structured u0, 16"))!=1 ||',
          'declarationCount(std::regex("dcl_uav_"))!=2 || declarationCount(std::regex("dcl_uav_structured u0, 16"))!=1 || declarationCount(std::regex("dcl_uav_structured u1, 16"))!=1 ||')
    patch('range.NumDescriptors=1;','range.NumDescriptors=2;')
    patch('hd.NumDescriptors=1+srvSpan;','hd.NumDescriptors=2+srvSpan;')
    patch('static_cast<SIZE_T>(1+slot)','static_cast<SIZE_T>(2+slot)')
    patch('static_cast<SIZE_T>(1+srv.reg)','static_cast<SIZE_T>(2+srv.reg)')
    patch('gpu.ptr+=descriptorIncrement;','gpu.ptr+=2*descriptorIncrement;')
    anchor='upload(seed.Get(),input,waterBytes); upload(cb.Get(),constants,cbBytes);'
    patch(anchor,anchor+'''
        auto debug=buffer(device.Get(),waterBytes,D3D12_HEAP_TYPE_DEFAULT,D3D12_RESOURCE_STATE_COPY_DEST,D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS);
        auto debugSeed=buffer(device.Get(),waterBytes,D3D12_HEAP_TYPE_UPLOAD,D3D12_RESOURCE_STATE_GENERIC_READ);
        auto debugReadback=buffer(device.Get(),waterBytes,D3D12_HEAP_TYPE_READBACK,D3D12_RESOURCE_STATE_COPY_DEST);
        upload(debugSeed.Get(),std::vector<char>(waterBytes,0),waterBytes);''')
    anchor='UINT descriptorIncrement=device->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);'
    patch(anchor,anchor+'''
        auto debugLocation=heap->GetCPUDescriptorHandleForHeapStart();debugLocation.ptr+=descriptorIncrement;
        device->CreateUnorderedAccessView(debug.Get(),nullptr,&view,debugLocation);''')
    anchor='list->CopyBufferRegion(water.Get(),0,seed.Get(),0,waterBytes);'
    patch(anchor,anchor+'''
            if(repeat){auto b=transition(debug.Get(),D3D12_RESOURCE_STATE_COPY_SOURCE,D3D12_RESOURCE_STATE_COPY_DEST);list->ResourceBarrier(1,&b);}
            list->CopyBufferRegion(debug.Get(),0,debugSeed.Get(),0,waterBytes);
            {auto b=transition(debug.Get(),D3D12_RESOURCE_STATE_COPY_DEST,D3D12_RESOURCE_STATE_UNORDERED_ACCESS);list->ResourceBarrier(1,&b);}''')
    patch('list->CopyResource(readback.Get(),water.Get());check(list->Close(),"Close");','''list->CopyResource(readback.Get(),water.Get());
            {auto b=transition(debug.Get(),D3D12_RESOURCE_STATE_UNORDERED_ACCESS,D3D12_RESOURCE_STATE_COPY_SOURCE);list->ResourceBarrier(1,&b);}
            list->CopyResource(debugReadback.Get(),debug.Get());check(list->Close(),"Close");''')
    anchor='if(beforeCopy)for(auto& srv:srvInputs){'
    patch(anchor,'''
            {void* ptr=nullptr;D3D12_RANGE reads={0,waterBytes};check(debugReadback->Map(0,&reads,&ptr),"MapDebugReadback");
             write(output/("trace_"+std::to_string(repeat)+".bin"),ptr,waterBytes);
             D3D12_RANGE noWrites={0,0};debugReadback->Unmap(0,&noWrites);}
            '''+anchor)
    # Snapshot parent already identifies edited bytecode; add observation metadata.
    patch('\\"explicit_snapshot_adaptation\\":true','\\"explicit_snapshot_adaptation\\":true,\\"register_observation_uav\\":1')
    text=text.replace('CBV b0, structured UAV u0 stride16,','CBV b0, structured UAV u0 normal and u1 observation stride16,')
    text=text.replace('water_snapshot_reference --snapshot','water_trace_reference --snapshot')
    target=here/'native_trace_reference/water_trace_reference.cpp';target.parent.mkdir(exist_ok=True);target.write_text(text,encoding='utf-8')
    shutil.copyfile(target,out/target.name)
    (out/'patches.json').write_text(json.dumps(dict(parent=parent,source=identity(target),patches=patches),indent=2),encoding='utf-8')
    vcvars=Path('D:/IDE_SOFTWARE/vs/VC/Auxiliary/Build/vcvars64.bat');batch=out/'build.cmd';exe=out/'water_trace_reference.exe'
    batch.write_text('@echo off\ncall "'+str(vcvars)+'"\nif errorlevel 1 exit /b %errorlevel%\ncl /Bv /nologo /std:c++17 /EHsc /O2 /W4 "'+str(out/target.name)+'" /Fe:"'+str(exe)+'" /Fo:"'+str(out/'water_trace_reference.obj')+'" /link d3d12.lib dxgi.lib d3dcompiler.lib dxguid.lib\nexit /b %errorlevel%\n',encoding='ascii')
    result=subprocess.run(['cmd.exe','/d','/c',str(batch)],cwd=out,capture_output=True)
    (out/'stdout.bin').write_bytes(result.stdout);(out/'stderr.bin').write_bytes(result.stderr)
    for name in ['build_trace_reference.py','evidence_contract.py']:shutil.copyfile(here/name,out/name)
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete' if not result.returncode else 'failed',verification_status='not_evaluated',exit_code=result.returncode,parent_source=parent,scope='Build only, not GPU or math validation',artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(exit_code=result.returncode)));raise SystemExit(result.returncode)


if __name__=='__main__':main()
