import json,os,time,hashlib,subprocess
from pathlib import Path
context_path=Path("D:/godot/project/sandcastle/test_output/water_material_natural/rdc_active_context.json")
end=time.monotonic()+10
context=None
while time.monotonic()<end:
    if context_path.exists():
        c=json.loads(context_path.read_text(encoding="utf-8-sig"))
        if c.get("host_pid")==os.getpid():context=c;break
    time.sleep(.05)
if context is None:raise RuntimeError("owned helper context missing")
out=Path(context["output"]);result={"host_pid":os.getpid(),"scope":"Own Godot frozen candidate capture and replay draw inventory, NOT ordinary cost gate.","pass":False}
target=None;controller=None;capture=None
try:
    import renderdoc as rd
    result["renderdoc"]=rd.GetVersionString()
    opts=rd.CaptureOptions();opts.allowVSync=False;opts.allowFullscreen=True
    args=["--path",context["project"],"--rendering-driver","d3d12","--resolution","1920x1080","--disable-vsync","--log-file",str(out/"godot.log"),"--script","res://tests/water_material_natural/rdc_frame_probe.gd","--","--output="+str(out),"--scene=res://scenes/water_material_natural_candidate/style_height_coupled.tscn","--tick=360","--init-timeout-s=180","--lighting-ablation","--checkpoint="+context["checkpoint"]]
    launched=rd.ExecuteAndInject(context["godot"],context["project"],subprocess.list2cmdline(args),[],str(out/"candidate"),opts,False)
    result["command"]=[context["godot"]]+args;result["ident"]=launched.ident
    if launched.ident==0:raise RuntimeError("capture injection failed")
    target=rd.CreateTargetControl("",launched.ident,"water-natural-owned",False)
    if target is None:raise RuntimeError("target connection failed")
    result["target_pid"]=target.GetPID();end=time.monotonic()+180
    (out/"capture_owner.json").write_text(json.dumps(result))
    while not (out/"capture_ready.json").exists() and target.Connected() and time.monotonic()<end:target.ReceiveMessage(None)
    if not (out/"capture_ready.json").exists():raise RuntimeError("ready marker absent")
    ready=json.loads((out/"capture_ready.json").read_text())
    if ready["pid"]!=result["target_pid"] or ready["tick"]!=360:raise RuntimeError("ready identity mismatch")
    result["ready"]=ready;target.TriggerCapture(1)
    (out/"capture_go.json").write_text(json.dumps({"target_pid":target.GetPID()}))
    end=time.monotonic()+90
    while target.Connected() and time.monotonic()<end:target.ReceiveMessage(None)
    result["target_disconnected"]=not target.Connected()
    files=sorted(out.glob("*.rdc"));result["captures"]=[{"path":str(p),"size":p.stat().st_size,"sha256":hashlib.sha256(p.read_bytes()).hexdigest()} for p in files]
    if not files:raise RuntimeError("no captures")
    capture=rd.OpenCaptureFile();result["open_result"]=str(capture.OpenFile(str(files[0]),"",None))
    status,controller=capture.OpenCapture(rd.ReplayOptions(),None);result["replay_result"]=str(status)
    if controller is None:raise RuntimeError("replay failed")
    result["counter_api_doc"]=controller.FetchCounters.__doc__
    counters=list(controller.EnumerateCounters());result["counters"]=[{"id":int(k),"name":controller.DescribeCounter(k).name,"unit":str(controller.DescribeCounter(k).unit)} for k in counters]
    durations={}
    if rd.GPUCounter.EventGPUDuration in counters:
        for value in controller.FetchCounters([rd.GPUCounter.EventGPUDuration]):durations[value.eventId]=value.value.d
    def flatten(actions):
        for action in actions:
            yield action
            yield from flatten(action.children)
    draws=[]
    for a in flatten(controller.GetRootActions()):
        if not a.flags & rd.ActionFlags.Drawcall:continue
        controller.SetFrameEvent(a.eventId,True);pipe=controller.GetPipelineState()
        row={"event":a.eventId,"flags":str(a.flags),"indices":a.numIndices,"instances":a.numInstances,"duration_seconds":durations.get(a.eventId),"outputs":[str(v.resource) for v in pipe.GetOutputTargets()],"depth_output":str(pipe.GetDepthTarget().resource)}
        for name,stage in [("vs",rd.ShaderStage.Vertex),("ps",rd.ShaderStage.Fragment)]:
            refl=pipe.GetShaderReflection(stage);row[name]={"id":str(pipe.GetShader(stage)),"sha256":hashlib.sha256(bytes(refl.rawBytes)).hexdigest() if refl else None,"raw_size":len(refl.rawBytes) if refl else None,"entry":refl.entryPoint if refl else None}
        draws.append(row)
    result["draws"]=draws;result["pass"]=bool(draws) and result["target_disconnected"] and (out/"capture_complete.json").exists()
except Exception as error:result["error"]=repr(error)
finally:
    if controller is not None:controller.Shutdown()
    if capture is not None:capture.Shutdown()
    if target is not None:target.Shutdown()
    (out/"capture_inventory.json").write_text(json.dumps(result,indent=2),encoding="utf-8")
os._exit(0 if result["pass"] else 1)
