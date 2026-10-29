"""Read-only supplemental resource usage/subresource evidence; qrenderdoc --python."""
import hashlib
import json
import os
import traceback
from pathlib import Path

ROOT = Path('D:/godot/project/sandcastle')
SOURCE = ROOT / 'sandcastlegame/test1.rdc'
SCRIPT = ROOT / 'docs/competitor/tools/export_shader_execution_views.py'
OUT = Path(os.environ['SHADER_VIEWS_OUT'])
assert OUT.is_absolute() and str(OUT).isascii()
OUT.mkdir(parents=True, exist_ok=False)

def identity(p):
    return dict(path=p.as_posix(), bytes=p.stat().st_size, sha256=hashlib.sha256(p.read_bytes()).hexdigest())

report = dict(source=identity(SOURCE), script=identity(SCRIPT), usage={}, events=[], success=False)
controller = cap = None
try:
    import renderdoc as rd
    assert report['source']['sha256'] == '761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2'
    report['version'] = rd.GetVersionString()
    report['tool'] = identity(Path('D:/other_software/RenderDoc/qrenderdoc.exe'))
    report['command'] = 'D:/other_software/RenderDoc/qrenderdoc.exe --python ' + SCRIPT.as_posix()
    report['environment'] = {'SHADER_VIEWS_OUT': str(OUT)}
    cap = rd.OpenCaptureFile()
    report['open'] = str(cap.OpenFile(str(SOURCE), '', None))
    status, controller = cap.OpenCapture(rd.ReplayOptions(), None)
    report['replay'] = str(status)
    assert controller is not None
    wanted = {'139571', '139573', '139582', '139589', '139720', '139722', '139723', '139724'}
    for r in controller.GetResources():
        if str(r.resourceId).split('::')[-1] in wanted:
            report['usage'][str(r.resourceId)] = [dict(event=u.eventId, usage=str(u.usage)) for u in controller.GetUsage(r.resourceId)]
    for eid in [3503, 3510, 3867, 3872, 5006, 6083, 6196]:
        controller.SetFrameEvent(eid, True)
        pipe = controller.GetPipelineState()
        row = dict(event=eid, stages={})
        for label, stage in [('cs', rd.ShaderStage.Compute)] if eid < 4000 else [('vs',rd.ShaderStage.Vertex),('ps',rd.ShaderStage.Pixel)]:
            binding = []
            for access, desc in [('read',pipe.GetReadOnlyResources(stage)),('readwrite',pipe.GetReadWriteResources(stage))]:
                for used in desc:
                    d = used.descriptor
                    binding.append(dict(access=access,index=used.access.index,resource=str(d.resource),
                                        firstMip=d.firstMip,numMips=d.numMips,firstSlice=d.firstSlice,
                                        numSlices=d.numSlices,elementByteSize=d.elementByteSize))
            row['stages'][label] = binding
        report['events'].append(row)
    report['source_after'] = identity(SOURCE)
    report['success'] = report['source_after'] == report['source']
except Exception:
    report['error'] = traceback.format_exc()
finally:
    if controller: controller.Shutdown()
    if cap: cap.Shutdown()
    (OUT/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
os._exit(0 if report['success'] else 1)
