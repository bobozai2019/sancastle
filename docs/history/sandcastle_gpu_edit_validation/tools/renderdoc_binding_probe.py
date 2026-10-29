"""Inspect owned capture reflection; keep missing API information explicit."""
import json
import os
from pathlib import Path
import time
import hashlib

context_path=Path("D:/godot/project/sandcastle/task/sandcastle_gpu_edit_validation/tools/renderdoc_binding_context.json")
deadline=time.monotonic()+10
context=None
while time.monotonic()<deadline:
    if context_path.exists():
        context=json.loads(context_path.read_text(encoding="utf-8-sig"));break
    time.sleep(0.05)
if context is None or context["host_pid"]!=os.getpid(): raise RuntimeError("binding helper PID mismatch")
out=Path(context["output"])
rows=[]
controller=None
capture=None
try:
    import renderdoc as rd
    capture=rd.OpenCaptureFile()
    opened=capture.OpenFile(context["capture"],"",None)
    status,controller=capture.OpenCapture(rd.ReplayOptions(),None)
    if controller is None: raise RuntimeError(str(status))
    def flatten(actions):
        for action in actions:
            yield action
            yield from flatten(action.children)
    api={}
    textures={texture.resourceId:texture for texture in controller.GetTextures()}
    for action in flatten(controller.GetRootActions()):
        if not action.flags & rd.ActionFlags.Dispatch: continue
        controller.SetFrameEvent(action.eventId,True)
        pipeline=controller.GetPipelineState()
        shader=pipeline.GetShader(rd.ShaderStage.Compute)
        reflection=pipeline.GetShaderReflection(rd.ShaderStage.Compute)
        if not api:
            api={name:getattr(getattr(pipeline,name,None),"__doc__",None) for name in dir(pipeline) if any(word in name.lower() for word in ("constant","descriptor","resource"))}
            api["controller_constants"]={name:getattr(getattr(controller,name,None),"__doc__",None) for name in dir(controller) if any(word in name.lower() for word in ("constant","descriptor","cbuffer"))}
        row={"event":action.eventId,"shader":str(shader),"dimensions":list(action.dispatchDimension),"reflection_missing":reflection is None}
        if reflection is not None:
            raw_shader=bytes(reflection.rawBytes)
            shader_name="binding_%d_shader_%s.bin"%(os.getpid(),str(shader).replace("::","_"))
            (out/shader_name).write_bytes(raw_shader)
            row["native_shader"]={"path":shader_name,"encoding":str(reflection.encoding),"size":len(raw_shader),"sha256":hashlib.sha256(raw_shader).hexdigest()}
            row["readonly"]=[resource.name for resource in reflection.readOnlyResources]
            row["readwrite"]=[resource.name for resource in reflection.readWriteResources]
            row["constants"]=[]
            row["resource_bindings"]=[]
            for used in pipeline.GetReadWriteResources(rd.ShaderStage.Compute):
                access=used.access
                descriptor=used.descriptor
                row["resource_bindings"].append({"reflection_index":access.index,"resource":str(descriptor.resource),"view":str(descriptor.view),"format":str(descriptor.format.Name()),"type":str(descriptor.type),"byte_offset":descriptor.byteOffset,"byte_size":descriptor.byteSize})
                if context.get("export_sand",False) and access.index<len(reflection.readWriteResources):
                    name=reflection.readWriteResources[access.index].name
                    if name in ("sand_in","sand_out","sand_src","sand_dst") and descriptor.resource in textures:
                        texture=textures[descriptor.resource]
                        data=bytes(controller.GetTextureData(descriptor.resource,rd.Subresource()))
                        filename="binding_%d_event_%d_%s.bin"%(os.getpid(),action.eventId,name)
                        (out/filename).write_bytes(data)
                        row["resource_bindings"][-1]["export"]={"path":filename,"size":len(data),"sha256":hashlib.sha256(data).hexdigest(),"width":texture.width,"height":texture.height,"format":texture.format.Name(),"selection":"SetFrameEvent(event, True), post-event replay"}
            for index,block in enumerate(reflection.constantBlocks):
                entry={"index":index,"name":block.name,"byte_size":block.byteSize,"variables":[{"name":variable.name,"offset":variable.byteOffset,"type":variable.type.name} for variable in block.variables]}
                try:
                    bound=pipeline.GetConstantBlock(rd.ShaderStage.Compute,index,0)
                    entry["bound_fields"]=dir(bound)
                    descriptor=bound.descriptor
                    entry["descriptor_fields"]=dir(descriptor)
                    entry["resourceId"]=str(descriptor.resource)
                    for key in ("byteOffset","byteSize"):
                        entry[key]=str(getattr(descriptor,key,"missing"))
                    if hasattr(descriptor,"inlineData"): entry["inline_hex"]=bytes(descriptor.inlineData).hex()
                    if descriptor.resource!=rd.ResourceId.Null():
                        data=controller.GetBufferData(descriptor.resource,descriptor.byteOffset,descriptor.byteSize)
                        entry["buffer_hex"]=bytes(data).hex()
                    values=controller.GetCBufferVariableContents(pipeline.GetComputePipelineObject(),shader,rd.ShaderStage.Compute,pipeline.GetShaderEntryPoint(rd.ShaderStage.Compute),index,descriptor.resource,descriptor.byteOffset,descriptor.byteSize)
                    entry["decoded"]=[{"name":v.name,"f32":list(v.value.f32v),"u32":list(v.value.u32v)} for v in values]
                    entry["decoded_scope"]="Diagnostic only: unknown reflection members may decode to zero; raw buffer_hex is authoritative."
                except Exception as error: entry["binding_error"]=repr(error)
                row["constants"].append(entry)
            row["reflection_fields"]=dir(reflection)
        rows.append(row)
    tool_path=context_path.with_name("renderdoc_binding_probe.py")
    result={"pass":True,"capture":context["capture"],"capture_sha256":hashlib.sha256(Path(context["capture"]).read_bytes()).hexdigest(),"tool_sha256":hashlib.sha256(tool_path.read_bytes()).hexdigest(),"rows":rows,"api":api,"scope":"reflection and actual descriptors/constants; optional post-event native sand exports, not failure-pair diagnosis"}
except Exception as error:
    result={"pass":False,"rows":rows,"error":repr(error)}
finally:
    if controller is not None: controller.Shutdown()
    if capture is not None: capture.Shutdown()
name="binding_probe_pid_%d.json"%os.getpid()
(out/name).write_text(json.dumps(result,indent=2),encoding="utf-8")
(out/"binding_probe_latest.json").write_text(json.dumps({"report":name}),encoding="utf-8")
os._exit(0 if result["pass"] else 1)
