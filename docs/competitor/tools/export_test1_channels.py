"""Read-only focused export; qrenderdoc --python with absolute English paths."""
import hashlib
import json
import os
import traceback
from pathlib import Path

ROOT = Path('D:/godot/project/sandcastle')
SOURCE = ROOT / 'rdc/test1.rdc'
OUT = ROOT / 'docs/competitor/evidence/test1_channels_20261023'
OUT.mkdir(parents=True, exist_ok=False)
def identity(path):
    return dict(path=str(path), bytes=path.stat().st_size, sha256=hashlib.sha256(path.read_bytes()).hexdigest())
report = dict(source=identity(SOURCE), tool=identity(ROOT / 'docs/competitor/tools/export_test1_channels.py'), exports=[], success=False)
capture = controller = None
try:
    import renderdoc as rd
    report['version'] = rd.GetVersionString()
    assert report['source']['sha256'] == '761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2'
    capture = rd.OpenCaptureFile()
    report['open'] = str(capture.OpenFile(str(SOURCE), '', None))
    status, controller = capture.OpenCapture(rd.ReplayOptions(), None)
    report['replay'] = str(status)
    assert controller is not None
    controller.SetFrameEvent(5006, True)
    pipe = controller.GetPipelineState()
    for used in pipe.GetReadOnlyResources(rd.ShaderStage.Vertex):
        if used.access.index != 0:
            continue
        d = used.descriptor
        p = OUT / 'e5006_ground.bin'
        p.write_bytes(bytes(controller.GetBufferData(d.resource, d.byteOffset, d.byteSize)))
        report['exports'].append(dict(identity(p), kind='runtime_buffer', selector=f'E5006 VS t0 {d.resource} offset={d.byteOffset} length={d.byteSize}'))
    thumb = capture.GetThumbnail(rd.FileType.PNG, 2048)
    p = OUT / 'capture_thumbnail.png'
    p.write_bytes(bytes(thumb.data))
    report['exports'].append(dict(identity(p), kind='derived_capture_thumbnail', selector='CaptureFile.GetThumbnail(PNG,2048)'))
    report['source_after'] = identity(SOURCE)
    report['success'] = report['source_after'] == report['source'] and len(report['exports']) == 2
except Exception:
    report['error'] = traceback.format_exc()
finally:
    if controller is not None: controller.Shutdown()
    if capture is not None: capture.Shutdown()
    report['command'] = 'D:/other_software/RenderDoc/qrenderdoc.exe --python ' + str(ROOT / 'docs/competitor/tools/export_test1_channels.py')
    (OUT / 'manifest.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
os._exit(0 if report['success'] else 1)
