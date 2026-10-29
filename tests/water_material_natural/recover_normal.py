"""Run with RenderDoc's embedded Python: qrenderdoc --python <absolute script>."""
import hashlib
import json
import os
from pathlib import Path

ROOT = Path('D:/godot/project/sandcastle')
OUT = ROOT / 'test_output/water_material_natural/t00_normal_recovery'
OUT.mkdir(parents=True, exist_ok=True)
EXPECTED = '761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2'

def identity(path):
    return {'path': str(path), 'bytes': path.stat().st_size,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}

report = {'pass': False, 'sources': [], 'exports': [], 'missing': [
    'Historical raw snapshot and p02_water_texture_match.json absent; package equivalence not revalidated.',
    'Exact original UV/time formula unknown; downstream use is Godot adaptation.']}
capture = controller = None
try:
    import renderdoc as rd
    script = ROOT/'tests/water_material_natural/recover_normal.py'
    report['tool'] = {'version': rd.GetVersionString(), 'script': identity(script),
                      'command': 'D:/other_software/RenderDoc/qrenderdoc.exe --python ' + str(script)}
    for path in (ROOT/'sandcastlegame/test1.rdc', ROOT/'rdc/test1.rdc'):
        entry = identity(path)
        report['sources'].append(entry)
        if entry['sha256'] != EXPECTED:
            raise RuntimeError('Capture hash mismatch: ' + str(path))
    capture = rd.OpenCaptureFile()
    opened = capture.OpenFile(str(ROOT/'sandcastlegame/test1.rdc'), '', None)
    report['open'] = str(opened)
    status, controller = capture.OpenCapture(rd.ReplayOptions(), None)
    report['replay'] = str(status)
    if controller is None:
        raise RuntimeError(str(status))
    controller.SetFrameEvent(6083, True)
    pipeline = controller.GetPipelineState()
    reflection = pipeline.GetShaderReflection(rd.ShaderStage.Pixel)
    report['pixel_shader'] = str(pipeline.GetShader(rd.ShaderStage.Pixel))
    report['bindings'] = []
    normal = None
    for used in pipeline.GetReadOnlyResources(rd.ShaderStage.Pixel):
        descriptor = used.descriptor
        row = {'reflection_index': used.access.index, 'resource': str(descriptor.resource),
               'format': descriptor.format.Name(), 'type': str(descriptor.type)}
        report['bindings'].append(row)
        if str(descriptor.resource) == 'ResourceId::681':
            normal = descriptor.resource
    if normal is None:
        raise RuntimeError('Confirmed normal not bound at E6083')
    texture = next(t for t in controller.GetTextures() if t.resourceId == normal)
    report['normal'] = {'width': texture.width, 'height': texture.height,
                        'format': texture.format.Name(), 'mips': texture.mips,
                        'selection': 'E6083 post-event; ResourceId::681 mip0 slice0 sample0'}
    data = bytes(controller.GetTextureData(normal, rd.Subresource()))
    if texture.width != 1024 or texture.height != 1024 or len(data) != 4194304:
        raise RuntimeError('Unexpected normal dimensions/bytes')
    raw = OUT/'normal_681_mip0_rgba8.bin'
    raw.write_bytes(data)
    report['exports'].append(dict(identity(raw), kind='runtime_raw_texels'))
    shader = OUT/'event_6083_pixel_shader.bin'
    shader.write_bytes(bytes(reflection.rawBytes))
    report['exports'].append(dict(identity(shader), kind='compiled_shader_not_HLSL'))
    report['api_docs'] = {'SaveTexture': controller.SaveTexture.__doc__}
    save = rd.TextureSave()
    save.resourceId = normal
    save.mip = 0
    save.destType = rd.FileType.PNG
    png = OUT/'normal_681_mip0.png'
    report['png_save'] = str(controller.SaveTexture(save, str(png)))
    if not png.is_file():
        raise RuntimeError('PNG export missing')
    report['exports'].append(dict(identity(png), kind='derived_png'))
    report['pass'] = True
except Exception as error:
    report['error'] = repr(error)
finally:
    if controller is not None:
        controller.Shutdown()
    if capture is not None:
        capture.Shutdown()
    (OUT/'manifest.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
os._exit(0 if report['pass'] else 1)
