"""Read-only geometry evidence, run with RenderDoc 1.46 qrenderdoc --python."""
import hashlib
import json
import os
import struct
import traceback
from pathlib import Path

ROOT = Path('D:/godot/project/sandcastle')
SOURCE = ROOT / 'sandcastlegame/test1.rdc'
OUT = Path(os.environ.get('TEST1_GEOMETRY_OUT', str(ROOT / 'test_output/test1_geometry_20261018/replay_v3')))
EXPECTED = '761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2'
OUT.mkdir(parents=True, exist_ok=False)

def identity(path):
    return {'path': str(path), 'bytes': path.stat().st_size,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}

def flatten(actions):
    for action in actions:
        yield action
        yield from flatten(action.children)

SCRIPT = ROOT / 'docs/competitor/tools/export_test1_geometry.py'
report = {'source': identity(SOURCE), 'script': identity(SCRIPT),
          'command': 'D:/other_software/RenderDoc/qrenderdoc.exe --python ' + str(SCRIPT),
          'scope': 'Captured sand geometry and water fields only; no business code or time-series claims',
          'exports': [], 'events': [], 'pass': False}

def export(name, raw, selector, kind):
    p = OUT / name
    p.write_bytes(bytes(raw))
    record = dict(identity(p), selector=selector, kind=kind)
    report['exports'].append(record)
    return record

def fields(value):
    result = {}
    for key in dir(value):
        if key.startswith('_') or key in ('this', 'thisown'):
            continue
        try:
            v = getattr(value, key)
            if not callable(v):
                result[key] = v if isinstance(v, (bool, int, float, str)) else str(v)
        except Exception:
            pass
    return result

capture = controller = None
try:
    import renderdoc as rd
    assert report['source']['sha256'] == EXPECTED
    report['version'] = rd.GetVersionString()
    capture = rd.OpenCaptureFile()
    report['open'] = str(capture.OpenFile(str(SOURCE), '', None))
    status, controller = capture.OpenCapture(rd.ReplayOptions(), None)
    report['replay'] = str(status)
    assert controller is not None
    actions = {a.eventId: a for a in flatten(controller.GetRootActions())}
    for event in (5006, 5018, 5030, 6083):
        controller.SetFrameEvent(event, True)
        pipe = controller.GetPipelineState()
        action = actions[event]
        row = {'event': event, 'selection': 'SetFrameEvent(event, True); post-event',
               'action': fields(action), 'stages': {}}
        report['events'].append(row)
        for label, stage in (('vs', rd.ShaderStage.Vertex), ('ps', rd.ShaderStage.Pixel)):
            reflection = pipe.GetShaderReflection(stage)
            sr = {'shader': str(pipe.GetShader(stage)), 'constants': [], 'resources': [],
                  'output_signature': [fields(x) for x in reflection.outputSignature]}
            row['stages'][label] = sr
            if event not in (5006, 6083):
                continue
            prefix = 'e%d_%s' % (event, label)
            sr['shader_raw'] = export(prefix + '.dxbc', reflection.rawBytes, prefix + ' rawBytes', 'compiled_shader')
            sr['disassembly'] = export(prefix + '.txt', controller.DisassembleShader(pipe.GetGraphicsPipelineObject(), reflection, '').encode('utf-8'), prefix, 'derived_disassembly')
            for i, block in enumerate(reflection.constantBlocks):
                d = pipe.GetConstantBlock(stage, i, 0).descriptor
                size = min(d.byteSize, block.byteSize)
                raw = bytes(controller.GetBufferData(d.resource, d.byteOffset, size))
                cr = {'index': i, 'descriptor': fields(d), 'size': size,
                      'float4': [list(struct.unpack_from('<4f', raw, n)) for n in range(0, len(raw)-15, 16)]}
                cr['raw'] = export(prefix + '_cb%d.bin' % i, raw,
                    '%s cb%d %s offset%d length%d' % (prefix, i, d.resource, d.byteOffset, size), 'runtime_cbuffer')
                sr['constants'].append(cr)
            for used in pipe.GetReadOnlyResources(stage):
                d = used.descriptor
                br = {'index': used.access.index, 'descriptor': fields(d)}
                if label == 'vs' and 0 < d.byteSize <= 16*1024*1024:
                    br['raw'] = export(prefix + '_buffer%d.bin' % used.access.index,
                        controller.GetBufferData(d.resource, d.byteOffset, d.byteSize),
                        '%s t-index%d %s offset%d length%d' % (prefix, used.access.index, d.resource, d.byteOffset, d.byteSize), 'runtime_buffer')
                sr['resources'].append(br)
        count = 2145 if event == 6083 else 4225
        mesh = controller.GetPostVSData(0, 0, rd.MeshDataStage.VSOut)
        row['mesh'] = fields(mesh)
        row['vsout_records'] = count
        raw = bytes(controller.GetBufferData(mesh.vertexResourceId, mesh.vertexByteOffset, mesh.vertexByteStride * count))
        assert len(raw) == mesh.vertexByteStride * count
        row['vsout'] = export('e%d_vsout.bin' % event, raw,
            'E%d VSOut instance0 view0 %s offset%d stride%d records%d' % (event, mesh.vertexResourceId, mesh.vertexByteOffset, mesh.vertexByteStride, count), 'runtime_vsout')
        (OUT / 'manifest_partial.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    report['source_after'] = identity(SOURCE)
    report['pass'] = report['source'] == report['source_after']
except Exception:
    report['error'] = traceback.format_exc()
finally:
    if controller is not None:
        controller.Shutdown()
    if capture is not None:
        capture.Shutdown()
    (OUT / 'manifest.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
os._exit(0 if report['pass'] else 1)
