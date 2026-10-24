"""Read-only test1 foam evidence; run with qrenderdoc --python."""
import hashlib
import json
import os
import traceback
from pathlib import Path

ROOT = Path('D:/godot/project/sandcastle')
SOURCE = ROOT / 'sandcastlegame/test1.rdc'
OUT = ROOT / 'docs/competitor/evidence/foam_comparison_20261024/rdc'
SCRIPT = ROOT / 'docs/competitor/tools/export_foam_comparison.py'
EXPECTED = '761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2'

def identity(path):
    return {'path': path.as_posix(), 'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}

def save(name, data, selector, kind):
    path = OUT / name
    path.write_bytes(bytes(data))
    row = dict(identity(path), selector=selector, kind=kind)
    report['exports'].append(row)
    return row

def flatten(actions):
    for action in actions:
        yield action
        yield from flatten(action.children)

OUT.mkdir(parents=True, exist_ok=False)
report = {'source': identity(SOURCE), 'script': identity(SCRIPT), 'exports': [], 'events': [], 'pass': False,
          'scope': 'Captured foam state, geometry and shading; no original lifetime, emission or real-time cost claim.'}
cap = controller = None
try:
    import renderdoc as rd
    assert report['source']['sha256'] == EXPECTED
    report['tool'] = {'version': rd.GetVersionString(), 'command': 'D:/other_software/RenderDoc/qrenderdoc.exe --python ' + SCRIPT.as_posix()}
    cap = rd.OpenCaptureFile()
    report['open'] = str(cap.OpenFile(str(SOURCE), '', None))
    status, controller = cap.OpenCapture(rd.ReplayOptions(), None)
    report['replay'] = str(status)
    if controller is None:
        raise RuntimeError(str(status))
    textures = {t.resourceId: t for t in controller.GetTextures()}
    buffers = {b.resourceId: b for b in controller.GetBuffers()}
    actions = {a.eventId: a for a in flatten(controller.GetRootActions())}
    for event in (1550, 1634, 3867, 3872, 6196):
        controller.SetFrameEvent(event, True)
        pipe = controller.GetPipelineState()
        action = actions[event]
        row = {'event': event, 'num_indices': action.numIndices, 'num_instances': action.numInstances, 'stages': {}}
        report['events'].append(row)
        stages = [('vs', rd.ShaderStage.Vertex), ('ps', rd.ShaderStage.Pixel)] if event == 6196 else [('cs', rd.ShaderStage.Compute)]
        for label, stage in stages:
            refl = pipe.GetShaderReflection(stage)
            prefix = f'e{event}_{label}'
            sr = {'constants': [], 'resources': []}
            row['stages'][label] = sr
            save(prefix + '.dxbc', refl.rawBytes, f'E{event} {label} rawBytes', 'compiled_shader')
            pipeline = pipe.GetGraphicsPipelineObject() if event == 6196 else pipe.GetComputePipelineObject()
            save(prefix + '.asm', controller.DisassembleShader(pipeline, refl, '').encode('utf-8'), f'E{event} {label} disassembly', 'derived_disassembly')
            for index, block in enumerate(refl.constantBlocks):
                d = pipe.GetConstantBlock(stage, index, 0).descriptor
                length = min(d.byteSize, block.byteSize)
                sr['constants'].append(save(prefix + f'_cb{index}.bin', controller.GetBufferData(d.resource, d.byteOffset, length), f'E{event} {label} cb{index} {d.resource} offset={d.byteOffset} length={length}', 'runtime_constants'))
            for access, resources in [('read', pipe.GetReadOnlyResources(stage)), ('write', pipe.GetReadWriteResources(stage))]:
                for used in resources:
                    d = used.descriptor
                    resource = str(d.resource)
                    entry = {'access': access, 'index': used.access.index, 'resource': resource}
                    sr['resources'].append(entry)
                    rid = resource.split('::')[-1]
                    if d.resource in textures:
                        tex = textures[d.resource]
                        entry['texture'] = {'width': tex.width, 'height': tex.height, 'format': tex.format.Name()}
                        if tex.width * tex.height <= 1024 * 512:
                            entry['raw'] = save(prefix + f'_{access}_{rid}.bin', controller.GetTextureData(d.resource, rd.Subresource()), f'E{event} {label} {access} index={used.access.index} {resource} mip0 slice0 sample0', 'runtime_texels')
                    elif d.resource in buffers:
                        length = buffers[d.resource].length
                        if length <= 16 * 1024 * 1024:
                            entry['raw'] = save(prefix + f'_{access}_{rid}.bin', controller.GetBufferData(d.resource, 0, length), f'E{event} {label} {access} index={used.access.index} {resource} whole buffer offset0 length={length}', 'runtime_buffer')
            if event == 6196 and label == 'vs':
                mesh = controller.GetPostVSData(0, 0, rd.MeshDataStage.VSOut)
                length = action.numInstances * 4 * mesh.vertexByteStride
                row['vsout'] = save('e6196_vsout.bin', controller.GetBufferData(mesh.vertexResourceId, mesh.vertexByteOffset, length), f'E6196 VSOut instance0 view0 {mesh.vertexResourceId} offset={mesh.vertexByteOffset} stride={mesh.vertexByteStride} requested_bytes={length}', 'runtime_vsout')
                row['vsout_stride'] = mesh.vertexByteStride
        (OUT / 'manifest_partial.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    thumb = cap.GetThumbnail(rd.FileType.PNG, 2048)
    save('capture_thumbnail.png', thumb.data, 'CaptureFile.GetThumbnail PNG maxsize2048', 'derived_thumbnail')
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
