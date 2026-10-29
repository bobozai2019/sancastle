// Instrumented original UAV alias capture / fixed read-stream adaptation. Never unmodified original execution.
#include <windows.h>
#include <d3d12.h>
#include <d3dcompiler.h>
#include <d3d11shader.h>
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <regex>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>
using Microsoft::WRL::ComPtr;
namespace fs = std::filesystem;

static void check(HRESULT result, const char* operation) {
    if (FAILED(result)) {
        char code[32]; sprintf_s(code, "0x%08lx", static_cast<unsigned long>(result));
        throw std::runtime_error(std::string(operation) + ":" + code);
    }
}
static std::vector<char> read(const std::string& path) {
    std::ifstream stream(path, std::ios::binary | std::ios::ate);
    if (!stream) throw std::runtime_error("INPUT_MISSING:" + path);
    auto length = stream.tellg();
    if (length <= 0) throw std::runtime_error("EMPTY_INPUT:" + path);
    std::vector<char> bytes(static_cast<size_t>(length));
    stream.seekg(0); stream.read(bytes.data(), bytes.size());
    if (!stream) throw std::runtime_error("SHORT_INPUT:" + path);
    return bytes;
}
static void write(const fs::path& path, const void* data, size_t length) {
    std::ofstream stream(path, std::ios::binary);
    stream.write(static_cast<const char*>(data), length);
    if (!stream) throw std::runtime_error("WRITE_FAILED");
}
static D3D12_RESOURCE_BARRIER transition(ID3D12Resource* resource, D3D12_RESOURCE_STATES before, D3D12_RESOURCE_STATES after) {
    D3D12_RESOURCE_BARRIER b = {};
    b.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    b.Transition.pResource = resource; b.Transition.StateBefore = before;
    b.Transition.StateAfter = after; b.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
    return b;
}
static ComPtr<ID3D12Resource> buffer(ID3D12Device* device, UINT64 bytes, D3D12_HEAP_TYPE type,
                                    D3D12_RESOURCE_STATES state, D3D12_RESOURCE_FLAGS flags = D3D12_RESOURCE_FLAG_NONE) {
    D3D12_HEAP_PROPERTIES heap = {}; heap.Type = type;
    D3D12_RESOURCE_DESC desc = {}; desc.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
    desc.Width = bytes; desc.Height = 1; desc.DepthOrArraySize = 1; desc.MipLevels = 1;
    desc.SampleDesc.Count = 1; desc.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR; desc.Flags = flags;
    ComPtr<ID3D12Resource> result;
    check(device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE, &desc, state, nullptr,
                                         IID_PPV_ARGS(&result)), "CreateCommittedResource");
    return result;
}
static void upload(ID3D12Resource* resource, const std::vector<char>& data, size_t capacity) {
    void* ptr = nullptr; D3D12_RANGE empty = {0, 0};
    check(resource->Map(0, &empty, &ptr), "MapUpload");
    memset(ptr, 0, capacity); memcpy(ptr, data.data(), data.size());
    D3D12_RANGE written = {0, capacity}; resource->Unmap(0, &written);
}

struct SrvInput {
    UINT reg=0;
    bool texture=false;
    ComPtr<ID3D12Resource> resource, seed, before;
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint={};
    UINT64 bytes=0;
};

int main(int argc, char** argv) {
    try {
        std::map<std::string, std::string> args;
        for (int i=1; i<argc; ++i) {
            if (std::string(argv[i]) == "--help") {
                std::cout << "water_readstream_reference [--stream-input <4MiB floor/sources or 20MiB simple replay records>] --program <DXBC> --input <uint4 512x256> --constants <CB0> --output <new ASCII directory> [--repeat 3] [--kind simple|floor|sources] [--before-copy 0|1] [--srv0 <8MiB sand>] [--texture0 <512x256 RG16F>] [--srv1 <8192B air>]\n";
                return 0;
            }
            if (i+1 >= argc) throw std::runtime_error("ARGUMENT_VALUE_MISSING");
            auto key=std::string(argv[i]); args[key]=argv[++i];
        }
        for (auto key : {"--program", "--input", "--constants", "--output"})
            if (!args.count(key)) throw std::runtime_error(std::string("ARGUMENT_MISSING:")+key);
        const std::set<std::string> allowed={"--program","--input","--constants","--output","--repeat","--kind","--before-copy","--srv0","--srv1","--texture0","--stream-input"};
        for(const auto& item:args)if(!allowed.count(item.first))throw std::runtime_error("UNSUPPORTED_ARGUMENT:"+item.first);
        std::string kind=args.count("--kind")?args["--kind"]:"simple";
        if(kind!="simple" && kind!="floor" && kind!="sources")throw std::runtime_error("UNSUPPORTED_KIND");
        const std::string copyOption=args.count("--before-copy")?args["--before-copy"]:"1";
        if(copyOption!="0" && copyOption!="1")throw std::runtime_error("INVALID_BEFORE_COPY_OPTION");
        bool beforeCopy=copyOption=="1";
        auto program=read(args["--program"]), input=read(args["--input"]), constants=read(args["--constants"]);
        constexpr size_t waterBytes=512*256*16;
        const UINT readCount=(kind=="floor" || kind=="sources")?1:5;
        const size_t streamBytes=waterBytes*readCount*2;
        bool replay=args.count("--stream-input")!=0;
        if (input.size()!=waterBytes) throw std::runtime_error("DEPENDENCY_SIZE_MISMATCH");
        if (program.size()<4 || memcmp(program.data(),"DXBC",4)) throw std::runtime_error("EXPECTED_EXPLICIT_ADAPTED_DXBC");
        ComPtr<ID3D11ShaderReflection> reflection;
        check(D3DReflect(program.data(),program.size(),IID_PPV_ARGS(&reflection)),"ReflectAdaptedDXBC");
        D3D11_SHADER_DESC shaderDesc={};check(reflection->GetDesc(&shaderDesc),"GetShaderDesc");
        UINT tx=0,ty=0,tz=0;reflection->GetThreadGroupSize(&tx,&ty,&tz);
        if(tx!=32 || ty!=32 || tz!=1)throw std::runtime_error("SELECTOR_MISMATCH:threads");
        D3D11_SHADER_BUFFER_DESC cbDesc={};UINT realConstantBlocks=0;
        for(UINT i=0;i<shaderDesc.ConstantBuffers;++i){
            D3D11_SHADER_BUFFER_DESC item={};check(reflection->GetConstantBufferByIndex(i)->GetDesc(&item),"GetConstantBufferDesc");
            // DXBC reflection also enumerates STRUCTURED resource-bind-info
            // layouts here. They are not CBV constant buffers.
            if(item.Type==D3D_CT_CBUFFER){cbDesc=item;++realConstantBlocks;}
        }
        std::cerr<<"DXBC_REFLECTION constant_buffer_entries="<<shaderDesc.ConstantBuffers<<" cbv_blocks="<<realConstantBlocks<<" bound_resources="<<shaderDesc.BoundResources<<"\n";
        // Shipping DXBC may omit RDEF reflection while retaining executable
        // resource declarations. Audit those declarations directly. Never
        // invent resource metadata when the reflection object is empty.
        ComPtr<ID3DBlob> disassembly;
        check(D3DDisassemble(program.data(),program.size(),D3D_DISASM_ENABLE_INSTRUCTION_NUMBERING,nullptr,&disassembly),"DisassembleDeclarations");
        std::string assembly(static_cast<const char*>(disassembly->GetBufferPointer()),disassembly->GetBufferSize());
        auto declarationCount=[&](const std::regex& expression){return static_cast<UINT>(std::distance(std::sregex_iterator(assembly.begin(),assembly.end(),expression),std::sregex_iterator()));};
        const std::regex cbDeclaration("dcl_constantbuffer [cC][bB]([0-9]+)\\[([0-9]+)\\], immediateIndexed");
        std::smatch match;
        if(declarationCount(cbDeclaration)!=1 || !std::regex_search(assembly,match,cbDeclaration) || match[1]!="0")throw std::runtime_error("DEPENDENCY_MISSING:cbv_declaration");
        UINT declaredConstantBytes=static_cast<UINT>(std::stoul(match[2]))*16;
        if(constants.size()!=declaredConstantBytes || constants.size()>2560 || constants.empty())throw std::runtime_error("DEPENDENCY_SIZE_MISMATCH:constants");
        if(realConstantBlocks && (realConstantBlocks!=1 || cbDesc.Size!=declaredConstantBytes))throw std::runtime_error("SELECTOR_MISMATCH:reflection_vs_declaration");
        UINT cbCount=0,uavCount=0,srvCount=0;
        for(UINT i=0;i<shaderDesc.BoundResources;++i){
            D3D11_SHADER_INPUT_BIND_DESC binding={};check(reflection->GetResourceBindingDesc(i,&binding),"GetResourceBindingDesc");
            if(binding.BindCount!=1)throw std::runtime_error("SELECTOR_MISMATCH:binding_count");
            if(binding.Type==D3D_SIT_CBUFFER && binding.BindPoint==0)++cbCount;
            else if(binding.Type==D3D_SIT_UAV_RWSTRUCTURED && binding.BindPoint<=1)++uavCount;
            else if(binding.Type==D3D_SIT_STRUCTURED && ((kind=="floor" && binding.BindPoint==0) || (kind=="sources" && binding.BindPoint==1) || binding.BindPoint==2))++srvCount;
            else if(binding.Type==D3D_SIT_TEXTURE && kind=="sources" && binding.BindPoint==0 && binding.Dimension==D3D_SRV_DIMENSION_TEXTURE2D)++srvCount;
            else throw std::runtime_error("SELECTOR_MISMATCH:unsupported_binding_or_counter");
        }
        UINT expectedSrv=(kind=="floor"?1:kind=="sources"?2:0)+(replay?1:0);
        constexpr UINT srvSpan=3;
        if(shaderDesc.BoundResources && (cbCount!=1 || uavCount!=2 || srvCount!=expectedSrv))throw std::runtime_error("DEPENDENCY_MISSING:binding_layout");
        if(declarationCount(std::regex("dcl_uav_"))!=2 || declarationCount(std::regex("dcl_uav_structured u0, 16"))!=1 || declarationCount(std::regex("dcl_uav_structured u1, 16"))!=1 ||
           assembly.find("imm_atomic_alloc")!=std::string::npos || assembly.find("imm_atomic_consume")!=std::string::npos ||
           assembly.find("dcl_sampler")!=std::string::npos)throw std::runtime_error("SELECTOR_MISMATCH:unsupported_uav_sampler_or_counter");
        UINT declaredSrvs=declarationCount(std::regex("dcl_resource_"));
        if(declaredSrvs!=expectedSrv)throw std::runtime_error("SELECTOR_MISMATCH:resource_declaration_count");
        const UINT waterLoads=declarationCount(std::regex(R"(ld_structured_indexable[^\r\n]* u0\.)"));
        const UINT streamLoads=declarationCount(std::regex(R"(ld_structured_indexable[^\r\n]* t2\.)"));
        if(replay){
            if(declarationCount(std::regex("dcl_resource_structured t2, 16"))!=1 || waterLoads!=0 || streamLoads!=readCount)
                throw std::runtime_error("NOT_DECLARED_READ_STREAM_REPLAY");
        }else if(waterLoads!=readCount || streamLoads!=0)throw std::runtime_error("NOT_DECLARED_ORIGINAL_ALIAS_CAPTURE");
        if(kind=="floor" && declarationCount(std::regex("dcl_resource_structured t0, 16"))!=1)throw std::runtime_error("SELECTOR_MISMATCH:sand_declaration");
        if(kind=="sources" && (declarationCount(std::regex("dcl_resource_structured t1, 16"))!=1 ||
           declarationCount(std::regex("dcl_resource_texture2d[^\\r\\n]* t0"))!=1))throw std::runtime_error("SELECTOR_MISMATCH:sources_declaration");
        std::map<UINT,std::vector<char>> srvBytes;
        if(replay){srvBytes[2]=read(args["--stream-input"]);
        if(srvBytes[2].size()!=streamBytes)throw std::runtime_error("DEPENDENCY_SIZE_MISMATCH:stream_t2");}
        if(kind=="floor"){
            if(!args.count("--srv0"))throw std::runtime_error("DEPENDENCY_MISSING:sand_t0");
            srvBytes[0]=read(args["--srv0"]);
            if(srvBytes[0].size()!=8388608)throw std::runtime_error("DEPENDENCY_SIZE_MISMATCH:sand");
        }
        if(kind=="sources"){
            if(!args.count("--texture0") || !args.count("--srv1"))throw std::runtime_error("DEPENDENCY_MISSING:sources");
            srvBytes[0]=read(args["--texture0"]);srvBytes[1]=read(args["--srv1"]);
            if(srvBytes[0].size()!=524288 || srvBytes[1].size()!=8192)throw std::runtime_error("DEPENDENCY_SIZE_MISMATCH:sources");
        }
        if(kind!="floor" && args.count("--srv0"))throw std::runtime_error("SELECTOR_MISMATCH:unused_srv0");
        if(kind!="sources" && (args.count("--texture0") || args.count("--srv1")))throw std::runtime_error("SELECTOR_MISMATCH:unused_sources");
        int count=args.count("--repeat") ? std::stoi(args["--repeat"]) : 3;
        if (count<1 || count>100) throw std::runtime_error("INVALID_REPEAT_COUNT");
        fs::path output=args["--output"];
        if (!output.is_absolute() || fs::exists(output)) throw std::runtime_error("OUTPUT_MUST_BE_NEW_ABSOLUTE");
        for (unsigned char c : output.string()) if (c>=128) throw std::runtime_error("OUTPUT_MUST_BE_ASCII");
        fs::create_directories(output);
        std::ofstream reflectionLog(output/"reflection.json");
        reflectionLog<<"{\"constant_buffer_entries\":"<<shaderDesc.ConstantBuffers<<",\"real_cbv_blocks\":"<<realConstantBlocks
                     <<",\"reflected_cbv_bytes\":"<<cbDesc.Size<<",\"declared_cbv_bytes\":"<<declaredConstantBytes<<",\"bound_resources\":"<<shaderDesc.BoundResources
                     <<",\"validation_method\":\"Executable DXBC declarations; RDEF reflection only when present\",\"bindings\":[";
        for(UINT i=0;i<shaderDesc.BoundResources;++i){
            D3D11_SHADER_INPUT_BIND_DESC d={};check(reflection->GetResourceBindingDesc(i,&d),"GetResourceBindingDesc");
            if(i)reflectionLog<<",";
            reflectionLog<<"{\"type\":"<<d.Type<<",\"register\":"<<d.BindPoint<<",\"count\":"<<d.BindCount<<",\"dimension\":"<<d.Dimension<<"}";
        }
        reflectionLog<<"]}";reflectionLog.close();
        write(output/"adapted_program.asm",assembly.data(),assembly.size());
        ComPtr<IDXGIFactory4> factory; check(CreateDXGIFactory2(0,IID_PPV_ARGS(&factory)),"CreateDXGIFactory2");
        ComPtr<IDXGIAdapter1> adapter;
        DXGI_ADAPTER_DESC1 adapterDesc={};
        // Match the discrete NVIDIA device on this evidence host explicitly.
        for (UINT i=0;;++i) {
            ComPtr<IDXGIAdapter1> candidate;
            if (factory->EnumAdapters1(i,&candidate)==DXGI_ERROR_NOT_FOUND) break;
            DXGI_ADAPTER_DESC1 desc={}; check(candidate->GetDesc1(&desc),"GetDesc1");
            if (desc.VendorId==0x10de && !(desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE)) {
                adapter=candidate; adapterDesc=desc; break;
            }
        }
        if (!adapter) throw std::runtime_error("MATCHING_NVIDIA_ADAPTER_MISSING");
        ComPtr<ID3D12Device> device; check(D3D12CreateDevice(adapter.Get(),D3D_FEATURE_LEVEL_11_0,IID_PPV_ARGS(&device)),"D3D12CreateDevice");
        D3D12_COMMAND_QUEUE_DESC qdesc={}; qdesc.Type=D3D12_COMMAND_LIST_TYPE_DIRECT;
        ComPtr<ID3D12CommandQueue> queue; check(device->CreateCommandQueue(&qdesc,IID_PPV_ARGS(&queue)),"CreateCommandQueue");
        D3D12_DESCRIPTOR_RANGE range={}; range.RangeType=D3D12_DESCRIPTOR_RANGE_TYPE_UAV;
        range.NumDescriptors=2; range.BaseShaderRegister=0; range.RegisterSpace=0; range.OffsetInDescriptorsFromTableStart=0;
        D3D12_ROOT_PARAMETER params[3]={};
        params[0].ParameterType=D3D12_ROOT_PARAMETER_TYPE_CBV; params[0].Descriptor.ShaderRegister=0;
        params[0].ShaderVisibility=D3D12_SHADER_VISIBILITY_ALL;
        params[1].ParameterType=D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
        params[1].DescriptorTable.NumDescriptorRanges=1; params[1].DescriptorTable.pDescriptorRanges=&range;
        params[1].ShaderVisibility=D3D12_SHADER_VISIBILITY_ALL;
        D3D12_DESCRIPTOR_RANGE srvRange={};srvRange.RangeType=D3D12_DESCRIPTOR_RANGE_TYPE_SRV;
        srvRange.NumDescriptors=srvSpan;srvRange.BaseShaderRegister=0;
        params[2].ParameterType=D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
        params[2].DescriptorTable.NumDescriptorRanges=1;params[2].DescriptorTable.pDescriptorRanges=&srvRange;
        params[2].ShaderVisibility=D3D12_SHADER_VISIBILITY_ALL;
        D3D12_ROOT_SIGNATURE_DESC sigdesc={}; sigdesc.NumParameters=expectedSrv?3:2; sigdesc.pParameters=params;
        ComPtr<ID3DBlob> signature, signatureError;
        check(D3D12SerializeRootSignature(&sigdesc,D3D_ROOT_SIGNATURE_VERSION_1,&signature,&signatureError),"SerializeRootSignature");
        write(output/"root_signature.bin",signature->GetBufferPointer(),signature->GetBufferSize());
        ComPtr<ID3D12RootSignature> signatureObject;
        check(device->CreateRootSignature(0,signature->GetBufferPointer(),signature->GetBufferSize(),IID_PPV_ARGS(&signatureObject)),"CreateRootSignature");
        D3D12_COMPUTE_PIPELINE_STATE_DESC pipeline={}; pipeline.pRootSignature=signatureObject.Get();
        pipeline.CS.pShaderBytecode=program.data(); pipeline.CS.BytecodeLength=program.size();
        ComPtr<ID3D12PipelineState> pso; check(device->CreateComputePipelineState(&pipeline,IID_PPV_ARGS(&pso)),"CreateAdaptedDXBCPipeline");
        auto water=buffer(device.Get(),waterBytes,D3D12_HEAP_TYPE_DEFAULT,D3D12_RESOURCE_STATE_COPY_DEST,D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS);
        auto seed=buffer(device.Get(),waterBytes,D3D12_HEAP_TYPE_UPLOAD,D3D12_RESOURCE_STATE_GENERIC_READ);
        constexpr size_t cbBytes=2560;
        auto cb=buffer(device.Get(),cbBytes,D3D12_HEAP_TYPE_UPLOAD,D3D12_RESOURCE_STATE_GENERIC_READ);
        auto readback=buffer(device.Get(),waterBytes,D3D12_HEAP_TYPE_READBACK,D3D12_RESOURCE_STATE_COPY_DEST);
        auto beforeReadback=buffer(device.Get(),waterBytes,D3D12_HEAP_TYPE_READBACK,D3D12_RESOURCE_STATE_COPY_DEST);
        upload(seed.Get(),input,waterBytes); upload(cb.Get(),constants,cbBytes);
        auto debug=buffer(device.Get(),streamBytes,D3D12_HEAP_TYPE_DEFAULT,D3D12_RESOURCE_STATE_COPY_DEST,D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS);
        auto debugSeed=buffer(device.Get(),streamBytes,D3D12_HEAP_TYPE_UPLOAD,D3D12_RESOURCE_STATE_GENERIC_READ);
        auto debugReadback=buffer(device.Get(),streamBytes,D3D12_HEAP_TYPE_READBACK,D3D12_RESOURCE_STATE_COPY_DEST);
        upload(debugSeed.Get(),std::vector<char>(streamBytes,0),streamBytes);
        D3D12_DESCRIPTOR_HEAP_DESC hd={}; hd.Type=D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV;
        hd.NumDescriptors=2+srvSpan; hd.Flags=D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE;
        ComPtr<ID3D12DescriptorHeap> heap; check(device->CreateDescriptorHeap(&hd,IID_PPV_ARGS(&heap)),"CreateDescriptorHeap");
        D3D12_UNORDERED_ACCESS_VIEW_DESC view={}; view.ViewDimension=D3D12_UAV_DIMENSION_BUFFER;
        view.Format=DXGI_FORMAT_UNKNOWN; view.Buffer.NumElements=512*256; view.Buffer.StructureByteStride=16;
        device->CreateUnorderedAccessView(water.Get(),nullptr,&view,heap->GetCPUDescriptorHandleForHeapStart());
        UINT descriptorIncrement=device->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);
        auto debugLocation=heap->GetCPUDescriptorHandleForHeapStart();debugLocation.ptr+=descriptorIncrement;
        auto streamView=view;streamView.Buffer.NumElements=static_cast<UINT>(streamBytes/16);
        device->CreateUnorderedAccessView(debug.Get(),nullptr,&streamView,debugLocation);
        // Null descriptors only fill undeclared holes; every declared SRV has real bytes.
        for(UINT slot=0;slot<srvSpan;++slot)if(!srvBytes.count(slot)){
            D3D12_SHADER_RESOURCE_VIEW_DESC nullView={};nullView.Shader4ComponentMapping=D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
            nullView.ViewDimension=D3D12_SRV_DIMENSION_BUFFER;nullView.Format=DXGI_FORMAT_UNKNOWN;
            nullView.Buffer.NumElements=1;nullView.Buffer.StructureByteStride=16;
            auto location=heap->GetCPUDescriptorHandleForHeapStart();location.ptr+=static_cast<SIZE_T>(2+slot)*descriptorIncrement;
            device->CreateShaderResourceView(nullptr,&nullView,location);
        }
        std::vector<SrvInput> srvInputs;
        for(const auto& entry:srvBytes){
            SrvInput srv;srv.reg=entry.first;srv.texture=kind=="sources" && entry.first==0;
            D3D12_SHADER_RESOURCE_VIEW_DESC srvView={};srvView.Shader4ComponentMapping=D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
            if(srv.texture){
                D3D12_RESOURCE_DESC desc={};desc.Dimension=D3D12_RESOURCE_DIMENSION_TEXTURE2D;
                desc.Width=512;desc.Height=256;desc.DepthOrArraySize=1;desc.MipLevels=1;
                desc.Format=DXGI_FORMAT_R16G16_FLOAT;desc.SampleDesc.Count=1;
                D3D12_HEAP_PROPERTIES hp={};hp.Type=D3D12_HEAP_TYPE_DEFAULT;
                check(device->CreateCommittedResource(&hp,D3D12_HEAP_FLAG_NONE,&desc,D3D12_RESOURCE_STATE_COPY_DEST,nullptr,IID_PPV_ARGS(&srv.resource)),"CreateObstacleTexture");
                UINT rows=0;UINT64 rowBytes=0;
                device->GetCopyableFootprints(&desc,0,1,0,&srv.footprint,&rows,&rowBytes,&srv.bytes);
                srv.seed=buffer(device.Get(),srv.bytes,D3D12_HEAP_TYPE_UPLOAD,D3D12_RESOURCE_STATE_GENERIC_READ);
                std::vector<char> padded(static_cast<size_t>(srv.bytes),0);
                for(UINT row=0;row<rows;++row)memcpy(padded.data()+srv.footprint.Offset+row*srv.footprint.Footprint.RowPitch,entry.second.data()+row*2048,2048);
                upload(srv.seed.Get(),padded,padded.size());
                srvView.ViewDimension=D3D12_SRV_DIMENSION_TEXTURE2D;srvView.Format=DXGI_FORMAT_R16G16_FLOAT;srvView.Texture2D.MipLevels=1;
            }else{
                srv.bytes=entry.second.size();srv.resource=buffer(device.Get(),srv.bytes,D3D12_HEAP_TYPE_UPLOAD,D3D12_RESOURCE_STATE_GENERIC_READ);
                upload(srv.resource.Get(),entry.second,static_cast<size_t>(srv.bytes));
                srvView.ViewDimension=D3D12_SRV_DIMENSION_BUFFER;srvView.Format=DXGI_FORMAT_UNKNOWN;
                srvView.Buffer.NumElements=static_cast<UINT>(srv.bytes/16);srvView.Buffer.StructureByteStride=16;
            }
            if(beforeCopy)srv.before=buffer(device.Get(),srv.bytes,D3D12_HEAP_TYPE_READBACK,D3D12_RESOURCE_STATE_COPY_DEST);
            auto cpu=heap->GetCPUDescriptorHandleForHeapStart();cpu.ptr+=static_cast<SIZE_T>(2+srv.reg)*descriptorIncrement;
            device->CreateShaderResourceView(srv.resource.Get(),&srvView,cpu);srvInputs.push_back(srv);
        }
        ComPtr<ID3D12CommandAllocator> allocator;
        check(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,IID_PPV_ARGS(&allocator)),"CreateCommandAllocator");
        ComPtr<ID3D12GraphicsCommandList> list;
        check(device->CreateCommandList(0,D3D12_COMMAND_LIST_TYPE_DIRECT,allocator.Get(),pso.Get(),IID_PPV_ARGS(&list)),"CreateCommandList");
        check(list->Close(),"InitialClose");
        ComPtr<ID3D12Fence> fence; check(device->CreateFence(0,D3D12_FENCE_FLAG_NONE,IID_PPV_ARGS(&fence)),"CreateFence");
        HANDLE fenceEvent=CreateEvent(nullptr,FALSE,FALSE,nullptr);
        if (!fenceEvent) throw std::runtime_error("CreateEventFailed");
        std::ofstream log(output/"execution.jsonl");
        for (int repeat=0;repeat<count;++repeat) {
            check(allocator->Reset(),"ResetAllocator"); check(list->Reset(allocator.Get(),pso.Get()),"ResetCommandList");
            if (repeat) {auto b=transition(water.Get(),D3D12_RESOURCE_STATE_COPY_SOURCE,D3D12_RESOURCE_STATE_COPY_DEST);list->ResourceBarrier(1,&b);}
            list->CopyBufferRegion(water.Get(),0,seed.Get(),0,waterBytes);
            if(repeat){auto b=transition(debug.Get(),D3D12_RESOURCE_STATE_COPY_SOURCE,D3D12_RESOURCE_STATE_COPY_DEST);list->ResourceBarrier(1,&b);}
            list->CopyBufferRegion(debug.Get(),0,debugSeed.Get(),0,streamBytes);
            {auto b=transition(debug.Get(),D3D12_RESOURCE_STATE_COPY_DEST,D3D12_RESOURCE_STATE_UNORDERED_ACCESS);list->ResourceBarrier(1,&b);}
            // Extra pre-dispatch copy proves restored bytes, and is explicitly
            // part of this controlled reference's observation perturbation.
            if(beforeCopy){
                auto before=transition(water.Get(),D3D12_RESOURCE_STATE_COPY_DEST,D3D12_RESOURCE_STATE_COPY_SOURCE);list->ResourceBarrier(1,&before);
                list->CopyResource(beforeReadback.Get(),water.Get());
            }
            auto toUav=transition(water.Get(),beforeCopy?D3D12_RESOURCE_STATE_COPY_SOURCE:D3D12_RESOURCE_STATE_COPY_DEST,D3D12_RESOURCE_STATE_UNORDERED_ACCESS);list->ResourceBarrier(1,&toUav);
            for(auto& srv:srvInputs){
                if(srv.texture){
                    if(repeat){auto b=transition(srv.resource.Get(),D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE,D3D12_RESOURCE_STATE_COPY_DEST);list->ResourceBarrier(1,&b);}
                    D3D12_TEXTURE_COPY_LOCATION from={},to={};from.pResource=srv.seed.Get();from.Type=D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;from.PlacedFootprint=srv.footprint;
                    to.pResource=srv.resource.Get();to.Type=D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
                    list->CopyTextureRegion(&to,0,0,0,&from,nullptr);
                    if(beforeCopy){
                        auto b=transition(srv.resource.Get(),D3D12_RESOURCE_STATE_COPY_DEST,D3D12_RESOURCE_STATE_COPY_SOURCE);list->ResourceBarrier(1,&b);
                        D3D12_TEXTURE_COPY_LOCATION target={};target.pResource=srv.before.Get();target.Type=D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;target.PlacedFootprint=srv.footprint;
                        list->CopyTextureRegion(&target,0,0,0,&to,nullptr);
                    }
                    auto b=transition(srv.resource.Get(),beforeCopy?D3D12_RESOURCE_STATE_COPY_SOURCE:D3D12_RESOURCE_STATE_COPY_DEST,D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);list->ResourceBarrier(1,&b);
                }else if(beforeCopy)list->CopyResource(srv.before.Get(),srv.resource.Get());
            }
            list->SetComputeRootSignature(signatureObject.Get());
            ID3D12DescriptorHeap* heaps[]={heap.Get()}; list->SetDescriptorHeaps(1,heaps);
            list->SetComputeRootConstantBufferView(0,cb->GetGPUVirtualAddress());
            list->SetComputeRootDescriptorTable(1,heap->GetGPUDescriptorHandleForHeapStart());
            if(expectedSrv){auto gpu=heap->GetGPUDescriptorHandleForHeapStart();gpu.ptr+=2*descriptorIncrement;list->SetComputeRootDescriptorTable(2,gpu);}
            list->Dispatch(16,8,1);
            auto after=transition(water.Get(),D3D12_RESOURCE_STATE_UNORDERED_ACCESS,D3D12_RESOURCE_STATE_COPY_SOURCE);list->ResourceBarrier(1,&after);
            list->CopyResource(readback.Get(),water.Get());
            {auto b=transition(debug.Get(),D3D12_RESOURCE_STATE_UNORDERED_ACCESS,D3D12_RESOURCE_STATE_COPY_SOURCE);list->ResourceBarrier(1,&b);}
            list->CopyResource(debugReadback.Get(),debug.Get());check(list->Close(),"Close");
            ID3D12CommandList* submitted[]={list.Get()};queue->ExecuteCommandLists(1,submitted);
            const UINT64 ticket=repeat+1;check(queue->Signal(fence.Get(),ticket),"Signal");
            if(fence->GetCompletedValue()<ticket) {
                check(fence->SetEventOnCompletion(ticket,fenceEvent),"SetEventOnCompletion");
                DWORD wait=WaitForSingleObject(fenceEvent,30000);
                if(wait!=WAIT_OBJECT_0) throw std::runtime_error("GPU_COMPLETION_TIMEOUT");
            }
            check(device->GetDeviceRemovedReason(),"DeviceRemovedReason");
            if(fence->GetCompletedValue()<ticket) throw std::runtime_error("FENCE_NOT_COMPLETE");
            for (int which=0;which<2;++which) {
                if(!which && !beforeCopy)continue;
                auto resource=which?readback.Get():beforeReadback.Get();
                void* ptr=nullptr;D3D12_RANGE reads={0,waterBytes};check(resource->Map(0,&reads,&ptr),"MapReadback");
                write(output/(std::string(which?"after_":"before_")+std::to_string(repeat)+".bin"),ptr,waterBytes);
                D3D12_RANGE noWrites={0,0};resource->Unmap(0,&noWrites);
            }
            
            {void* ptr=nullptr;D3D12_RANGE reads={0,streamBytes};check(debugReadback->Map(0,&reads,&ptr),"MapDebugReadback");
             write(output/("stream_"+std::to_string(repeat)+".bin"),ptr,streamBytes);
             D3D12_RANGE noWrites={0,0};debugReadback->Unmap(0,&noWrites);}
            if(beforeCopy)for(auto& srv:srvInputs){
                void* ptr=nullptr;D3D12_RANGE reads={0,static_cast<SIZE_T>(srv.bytes)};check(srv.before->Map(0,&reads,&ptr),"MapSRVBefore");
                if(srv.texture){
                    std::vector<char> packed(524288);
                    for(UINT row=0;row<256;++row)memcpy(packed.data()+row*2048,static_cast<char*>(ptr)+srv.footprint.Offset+row*srv.footprint.Footprint.RowPitch,2048);
                    write(output/("srv"+std::to_string(srv.reg)+"_before_"+std::to_string(repeat)+".bin"),packed.data(),packed.size());
                }else write(output/("srv"+std::to_string(srv.reg)+"_before_"+std::to_string(repeat)+".bin"),ptr,static_cast<size_t>(srv.bytes));
                D3D12_RANGE noWrites={0,0};srv.before->Unmap(0,&noWrites);
            }
            log << "{\"repeat\":" << repeat << ",\"fence_ticket\":" << ticket << ",\"fence_completed\":" << fence->GetCompletedValue()
                << ",\"restored_bytes\":" << waterBytes << ",\"dispatch\":[16,8,1],\"threads\":[32,32,1],\"before_copy\":"<<(beforeCopy?"true":"false")
                <<",\"kind\":\""<<kind<<"\",\"srv_count\":"<<expectedSrv<<",\"constant_bytes\":"<<constants.size()
                <<",\"counter_dependencies\":0,\"buffer_srv_heap\":\"immutable UPLOAD\",\"texture_srv_heap\":\"DEFAULT restored each dispatch\",\"binding\":\"CBV b0, structured UAV u0 normal and u1 observation stride16, u0 alias capture or explicit post-swizzle stream t2 replay; u1 readstream records\"}\n";
            log.flush();
        }
        CloseHandle(fenceEvent);
        std::ofstream env(output/"device.json");
        env << "{\"vendor_id\":"<<adapterDesc.VendorId<<",\"device_id\":"<<adapterDesc.DeviceId
            <<",\"adapter_luid_low\":"<<adapterDesc.AdapterLuid.LowPart<<",\"adapter_luid_high\":"<<adapterDesc.AdapterLuid.HighPart
            <<",\"dedicated_video_memory\":"<<adapterDesc.DedicatedVideoMemory<<",\"debug_layer\":false,\"queue\":\"DIRECT\",\"dxbc_unmodified\":false,\"explicit_readstream_adaptation\":true,\"readstream_output_uav\":1,\"before_copy\":"<<(beforeCopy?"true":"false")<<"}";
        std::cout<<"{\"operation_status\":\"complete\",\"repeats\":"<<count<<"}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
