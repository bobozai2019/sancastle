"""Read-only test1 inventory/selected shader evidence via qrenderdoc --python.

SHADER_AUDIT_OUT must be a new absolute ASCII directory.
SHADER_AUDIT_SELECTION optionally points to JSON [{event, stages, purpose}].
No GPU timing, business code, or live utilization is inferred by this exporter.
"""
import hashlib
import json
import os
import traceback
from pathlib import Path

ROOT = Path('D:/godot/project/sandcastle')
SOURCE = ROOT / 'sandcastlegame/test1.rdc'
SCRIPT = ROOT / 'docs/competitor/tools/export_shader_execution_audit.py'
EXPECTED = '761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2'
OUT = Path(os.environ['SHADER_AUDIT_OUT'])
assert OUT.is_absolute() and str(OUT).isascii()
OUT.mkdir(parents=True, exist_ok=False)

def identity(path):
    return {'path': path.as_posix(), 'bytes': path.stat().st_size,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}

report = {'source': identity(SOURCE), 'script': identity(SCRIPT), 'events': [],
          'exports': [], 'errors': [], 'pass': False,
          'scope': 'Captured actions and selected compiled shaders/bindings/constants. No live CPU/GPU utilization or original HLSL claim.'}

def write_json(name, data):
    (OUT / name).write_text(json.dumps(data, ensure_ascii=True, indent=2), encoding='utf-8')

def save(name, data, selector, kind):
    path = OUT / name
    path.write_bytes(bytes(data))
    item = dict(identity(path), selector=selector, kind=kind)
    report['exports'].append(item)
    return item

cap = controller = None
try:
    import renderdoc as rd
    assert report['source']['sha256'] == EXPECTED
    report['tool'] = {'version': rd.GetVersionString(),
                      'executable': identity(Path('D:/other_software/RenderDoc/qrenderdoc.exe')),
                      'command': 'D:/other_software/RenderDoc/qrenderdoc.exe --python ' + SCRIPT.as_posix(),
                      'environment': {k: os.environ.get(k) for k in ['SHADER_AUDIT_OUT', 'SHADER_AUDIT_SELECTION']}}
    write_json('progress.json', {'phase': 'open_capture'})
    cap = rd.OpenCaptureFile()
    report['open_file'] = str(cap.OpenFile(str(SOURCE), '', None))
    status, controller = cap.OpenCapture(rd.ReplayOptions(), None)
    report['open_capture'] = str(status)
    if controller is None:
        raise RuntimeError(str(status))
    sf = controller.GetStructuredFile()
    actions = {}
    inventory = []

    def walk(items, parents=()):
        for a in items:
            actions[a.eventId] = a
            try:
                name = a.GetName(sf)
            except Exception:
                name = a.customName
            flags = str(a.flags)
            if a.flags & (rd.ActionFlags.Dispatch | rd.ActionFlags.Drawcall):
                inventory.append({'event': a.eventId, 'name': name, 'markers': list(parents),
                                  'flags': flags, 'dispatch': bool(a.flags & rd.ActionFlags.Dispatch),
                                  'groups': list(a.dispatchDimension), 'indices': a.numIndices,
                                  'instances': a.numInstances})
            walk(a.children, parents + ((name,) if name else ()))
    walk(controller.GetRootActions())
    write_json('actions.json', inventory)
    report['actions'] = identity(OUT / 'actions.json')
    buffers = {b.resourceId: b for b in controller.GetBuffers()}
    textures = {t.resourceId: t for t in controller.GetTextures()}
    names = {r.resourceId: r.name for r in controller.GetResources()}
    resources = []
    for rid, b in buffers.items():
        resources.append({'resource': str(rid), 'name': names.get(rid), 'type': 'buffer', 'bytes': b.length})
    for rid, t in textures.items():
        resources.append({'resource': str(rid), 'name': names.get(rid), 'type': 'texture',
                          'width': t.width, 'height': t.height, 'depth': t.depth,
                          'mips': t.mips, 'arraysize': t.arraysize, 'format': t.format.Name()})
    write_json('resources.json', resources)
    report['resources'] = identity(OUT / 'resources.json')
    selection_path = os.environ.get('SHADER_AUDIT_SELECTION')
    selection = json.loads(Path(selection_path).read_text(encoding='utf-8')) if selection_path else []
    if selection_path:
        report['selection'] = identity(Path(selection_path))
    stage_map = {'cs': rd.ShaderStage.Compute, 'vs': rd.ShaderStage.Vertex,
                 'ps': rd.ShaderStage.Pixel, 'gs': rd.ShaderStage.Geometry,
                 'hs': rd.ShaderStage.Hull, 'ds': rd.ShaderStage.Domain}
    for spec in selection:
        eid = spec['event']
        write_json('progress.json', {'phase': 'export', 'event': eid, 'done': len(report['events']), 'total': len(selection)})
        controller.SetFrameEvent(eid, True)
        pipe = controller.GetPipelineState()
        a = actions[eid]
        row = {'event': eid, 'purpose': spec.get('purpose'), 'groups': list(a.dispatchDimension),
               'indices': a.numIndices, 'instances': a.numInstances, 'stages': {}}
        report['events'].append(row)
        for label in spec['stages']:
            stage = stage_map[label]
            refl = pipe.GetShaderReflection(stage)
            if refl is None:
                raise RuntimeError('missing reflection E%d %s' % (eid, label))
            prefix = 'e%d_%s' % (eid, label)
            sr = {'shader_resource': str(pipe.GetShader(stage)), 'constants': [], 'bindings': [],
                  'threads': list(refl.dispatchThreadsDimension) if label == 'cs' else None,
                  'readonly_names': [r.name for r in refl.readOnlyResources],
                  'readwrite_names': [r.name for r in refl.readWriteResources]}
            row['stages'][label] = sr
            sr['bytecode'] = save(prefix + '.dxbc', refl.rawBytes, 'E%d %s rawBytes' % (eid, label), 'compiled_shader')
            pipeline = pipe.GetComputePipelineObject() if label == 'cs' else pipe.GetGraphicsPipelineObject()
            sr['disassembly'] = save(prefix + '.asm', controller.DisassembleShader(pipeline, refl, '').encode('utf-8'),
                                     'E%d %s automatic disassembly' % (eid, label), 'derived_disassembly')
            for index, block in enumerate(refl.constantBlocks):
                d = pipe.GetConstantBlock(stage, index, 0).descriptor
                length = min(d.byteSize, block.byteSize)
                if length <= 0:
                    raise RuntimeError('empty constant block E%d %s %d' % (eid, label, index))
                raw = save(prefix + '_cb%d.bin' % index, controller.GetBufferData(d.resource, d.byteOffset, length),
                           'E%d %s cb%d %s offset=%d bytes=%d' % (eid, label, index, d.resource, d.byteOffset, length), 'runtime_constants')
                sr['constants'].append({'index': index, 'resource': str(d.resource), 'offset': d.byteOffset, 'bytes': length, 'raw': raw})
            for access, bound in [('read', pipe.GetReadOnlyResources(stage)), ('readwrite', pipe.GetReadWriteResources(stage))]:
                for used in bound:
                    d = used.descriptor
                    entry = {'access': access, 'index': used.access.index, 'resource': str(d.resource),
                             'name': names.get(d.resource), 'offset': d.byteOffset, 'bytes': d.byteSize,
                             'descriptor_type': str(d.type), 'format': d.format.Name()}
                    if d.resource in buffers:
                        entry['buffer_bytes'] = buffers[d.resource].length
                    if d.resource in textures:
                        t = textures[d.resource]
                        entry['texture'] = {'width': t.width, 'height': t.height, 'depth': t.depth,
                                            'mips': t.mips, 'format': t.format.Name()}
                    sr['bindings'].append(entry)
        write_json('manifest_partial.json', report)
    report['source_after'] = identity(SOURCE)
    report['pass'] = report['source'] == report['source_after'] and len(report['events']) == len(selection)
except Exception:
    report['errors'].append(traceback.format_exc())
finally:
    if controller is not None:
        controller.Shutdown()
    if cap is not None:
        cap.Shutdown()
    write_json('manifest.json', report)
os._exit(0 if report['pass'] else 1)
