"""Read-only replay of identified competitor visual draws; qrenderdoc --python this file."""
import hashlib
import json
import os
import struct
import traceback
from pathlib import Path

ROOT = Path('D:/godot/project/sandcastle')
OUT = ROOT / 'docs/competitor/evidence/material_quality_20261023/rdc'
SOURCE = ROOT / 'rdc/test1.rdc'
EXPECTED = '761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2'
OUT.mkdir(parents=True, exist_ok=True)

def identity(path):
    return {'path': str(path), 'bytes': path.stat().st_size,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}

def write_bytes(name, data, selector, kind):
    path = OUT / name
    path.write_bytes(bytes(data))
    row = dict(identity(path), selector=selector, kind=kind)
    report['exports'].append(row)
    return row

def scalar(value):
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    return str(value)

def fields(value, depth=2):
    result = {}
    for key in dir(value):
        if key.startswith('_') or key in ('this', 'thisown'):
            continue
        try:
            v = getattr(value, key)
            if callable(v):
                continue
            if isinstance(v, (str, int, float, bool)):
                result[key] = v
            elif isinstance(v, (list, tuple)):
                result[key] = [scalar(x) for x in v]
            else:
                result[key] = str(v)
        except Exception as error:
            result[key] = repr(error)
    return result

report = {'pass': False, 'sources': [identity(SOURCE)], 'exports': [], 'events': [],
          'scope': 'Read-only test1 captured visual draws. No business code. Compiled instructions are not original HLSL.'}
capture = controller = None
try:
    import renderdoc as rd
    if report['sources'][0]['sha256'] != EXPECTED:
        raise RuntimeError('Capture identity mismatch')
    script = ROOT / 'docs/competitor/tools/export_material_quality.py'
    report['tool'] = {'version': rd.GetVersionString(), 'script': identity(script),
                      'command': 'D:/other_software/RenderDoc/qrenderdoc.exe --python ' + str(script)}
    capture = rd.OpenCaptureFile()
    report['open'] = str(capture.OpenFile(str(SOURCE), '', None))
    status, controller = capture.OpenCapture(rd.ReplayOptions(), None)
    report['replay'] = str(status)
    if controller is None:
        raise RuntimeError(str(status))
    textures = {t.resourceId:t for t in controller.GetTextures()}
    report['api_docs'] = {name: getattr(controller, name).__doc__ for name in
                          ('DisassembleShader', 'DebugPixel', 'GetCBufferVariableContents')}
    exported_textures = set()
    for event in (5006, 6083):
        controller.SetFrameEvent(event, True)
        pipe = controller.GetPipelineState()
        row = {'event': event, 'selection': 'SetFrameEvent(event, True), post-event', 'stages': {},
               'outputs': [str(x.resource) for x in pipe.GetOutputTargets()],
               'depth_output': str(pipe.GetDepthTarget().resource)}
        report['events'].append(row)
        d3d = controller.GetD3D12PipelineState()
        row['output_merger'] = fields(d3d.outputMerger, 3) if d3d is not None else {'unavailable':True}
        for label, stage in (('vs', rd.ShaderStage.Vertex), ('ps', rd.ShaderStage.Pixel)):
            shader = pipe.GetShader(stage)
            refl = pipe.GetShaderReflection(stage)
            prefix = 'event_%d_%s' % (event, label)
            sr = {'shader': str(shader), 'constants': [], 'textures': [], 'samplers': []}
            row['stages'][label] = sr
            sr['bytecode'] = write_bytes(prefix+'.bin', refl.rawBytes, '%s %s' % (prefix, shader), 'compiled_shader')
            disassembly = controller.DisassembleShader(pipe.GetGraphicsPipelineObject(), refl, '')
            sr['disassembly'] = write_bytes(prefix+'_disassembly.txt', disassembly.encode('utf-8'),
                                            '%s automatic target' % prefix, 'derived_disassembly')
            for index, block in enumerate(refl.constantBlocks):
                bound = pipe.GetConstantBlock(stage, index, 0)
                descriptor = bound.descriptor
                byte_offset = descriptor.byteOffset
                byte_size = min(descriptor.byteSize, block.byteSize)
                data = bytes(controller.GetBufferData(descriptor.resource, byte_offset, byte_size))
                cr = {'index':index, 'name':block.name, 'reflection_bytes':block.byteSize,
                      'resource':str(descriptor.resource), 'byte_offset':byte_offset, 'byte_size':byte_size,
                      'bound':fields(bound,0),'access':fields(bound.access,0),'descriptor':fields(descriptor,0),
                      'variables':[fields(v,0) for v in block.variables],
                      'registers_float4': [list(struct.unpack_from('<4f',data,n)) for n in range(0,len(data)-15,16)]}
                cr['raw'] = write_bytes(prefix+'_cb%d.bin'%index, data,
                    '%s cb%d %s offset=%d size=%d; reflected declared range'%(prefix,index,descriptor.resource,byte_offset,byte_size), 'runtime_cbuffer_consumed_range')
                sr['constants'].append(cr)
            for used in pipe.GetReadOnlyResources(stage):
                d = used.descriptor
                tr = {'reflection_index':used.access.index, 'resource':str(d.resource),
                      'name':refl.readOnlyResources[used.access.index].name, 'descriptor':fields(d,1), 'view_format':d.format.Name()}
                sr['textures'].append(tr)
                if d.resource in textures:
                    tex = textures[d.resource]
                    tr['texture'] = dict(fields(tex,0), format_name=tex.format.Name())
                    if label == 'ps' and str(d.resource) in ('ResourceId::617','ResourceId::1105','ResourceId::681','ResourceId::3375','ResourceId::3386') and d.resource not in exported_textures:
                        data = controller.GetTextureData(d.resource,rd.Subresource())
                        tr['mip0_raw'] = write_bytes(prefix+'_texture_'+str(d.resource).split('::')[-1]+'_mip0.bin',data,
                            '%s %s mip0 slice0 sample0; 3D API returns whole mip volume'%(prefix,d.resource), 'runtime_raw_texels')
                        exported_textures.add(d.resource)
            for used in pipe.GetSamplers(stage):
                sr['samplers'].append({'access':fields(used.access,1),'sampler':fields(used.sampler,0),'filter':fields(used.sampler.filter,0)})
        (OUT/'manifest_partial.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    thumb = capture.GetThumbnail(rd.FileType.PNG, 2048)
    write_bytes('capture_thumbnail.png', thumb.data, 'CaptureFile.GetThumbnail(PNG,2048)', 'derived_thumbnail')
    report['source_after'] = identity(SOURCE)
    report['pass'] = report['source_after'] == report['sources'][0]
except Exception as error:
    report['error'] = repr(error)
    report['traceback'] = traceback.format_exc()
finally:
    if controller is not None:
        controller.Shutdown()
    if capture is not None:
        capture.Shutdown()
    (OUT/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
os._exit(0 if report['pass'] else 1)
