"""Read-only test41 E863 height stamp export; qrenderdoc --python."""
import hashlib
import json
import os
import struct
import traceback
from pathlib import Path

ROOT = Path('D:/godot/project/sandcastle')
SOURCE = ROOT / 'sandcastlegame/test41.rdc'
OUT = ROOT / 'test_output/competitor_stamp_20261015/replay_01'
SCRIPT = ROOT / 'tests/investigation/castle_stamp/export_paint.py'
EXPECTED = 'f1794a7235a79f7a73bd6f4085bef7ecbb3a7dc39ce8a8a7aac955ee5beb3c0d'
SHADER = 'd37af2736147fd90f62ecbf8230bb0162a961ba2b16bce44a29d02fb2cdb30aa'
OUT.mkdir(parents=True, exist_ok=False)


def identity(p):
    return {'path': str(p), 'bytes': p.stat().st_size,
            'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}


report = {'source': identity(SOURCE), 'script': identity(SCRIPT), 'event': 863,
          'scope': 'Captured GPU height editing only; tool identity, CPU placement rule and repeated placement unknown',
          'exports': [], 'constants': [], 'bindings': [], 'pass': False}


def export(name, data, selector):
    p = OUT / name
    p.write_bytes(bytes(data))
    row = dict(identity(p), selector=selector)
    report['exports'].append(row)
    return row


cap = controller = None
try:
    import renderdoc as rd
    assert report['source']['sha256'] == EXPECTED
    report['tool_version'] = rd.GetVersionString()
    report['command'] = 'D:/other_software/RenderDoc/qrenderdoc.exe --python ' + str(SCRIPT)
    cap = rd.OpenCaptureFile()
    report['open'] = str(cap.OpenFile(str(SOURCE), '', None))
    status, controller = cap.OpenCapture(rd.ReplayOptions(), None)
    report['replay'] = str(status)
    assert controller is not None
    controller.SetFrameEvent(863, True)
    pipe = controller.GetPipelineState()
    stage = rd.ShaderStage.Compute
    refl = pipe.GetShaderReflection(stage)
    report['shader'] = export('paint.dxbc', refl.rawBytes, 'test41 E863 CS rawBytes')
    assert report['shader']['sha256'] == SHADER
    export('paint.asm', controller.DisassembleShader(pipe.GetComputePipelineObject(), refl, '').encode('utf-8'), 'test41 E863 CS disassembly')
    for i, block in enumerate(refl.constantBlocks):
        d = pipe.GetConstantBlock(stage, i, 0).descriptor
        raw = bytes(controller.GetBufferData(d.resource, d.byteOffset, min(d.byteSize, block.byteSize)))
        report['constants'].append({'index': i, 'name': block.name,
            'float4': [list(struct.unpack_from('<4f', raw, n)) for n in range(0, len(raw)-15, 16)],
            'raw': export('cb%d.bin' % i, raw, 'CS cb%d resource %s offset %d' % (i, d.resource, d.byteOffset))})
    textures = {t.resourceId: t for t in controller.GetTextures()}
    for label, resources in [('readonly', pipe.GetReadOnlyResources(stage)), ('readwrite', pipe.GetReadWriteResources(stage))]:
        for used in resources:
            d = used.descriptor
            row = {'access': label, 'index': used.access.index, 'resource': str(d.resource),
                   'offset': d.byteOffset, 'bytes': d.byteSize, 'type': str(d.type)}
            name = label + '_' + str(used.access.index)
            if d.resource in textures:
                t = textures[d.resource]
                row['texture'] = {'width': t.width, 'height': t.height, 'format': t.format.Name()}
                if t.width * t.height <= 256*256:
                    row['raw'] = export(name + '.texels', controller.GetTextureData(d.resource, rd.Subresource()), 'test41 E863 %s mip0 slice0 sample0' % d.resource)
            elif 0 < d.byteSize <= 16*1024*1024:
                row['raw'] = export(name + '.bin', controller.GetBufferData(d.resource, d.byteOffset, d.byteSize), 'test41 E863 %s offset%d bytes%d' % (d.resource, d.byteOffset, d.byteSize))
            report['bindings'].append(row)
    report['source_after'] = identity(SOURCE)
    report['pass'] = report['source_after'] == report['source']
except Exception:
    report['error'] = traceback.format_exc()
finally:
    if controller is not None:
        controller.Shutdown()
    if cap is not None:
        cap.Shutdown()
    (OUT / 'manifest.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
os._exit(0 if report['pass'] else 1)
