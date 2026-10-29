"""Run via qrenderdoc --python: exact Gravel.Update hash in test1 dispatches."""
import hashlib
import json
import os
import traceback
from pathlib import Path

ROOT = Path('D:/godot/project/sandcastle')
OUT = ROOT / 'test_output/competitor_transport_20261012/replay_v2'
SOURCE = ROOT / 'sandcastlegame/test1.rdc'
EXPECTED = '761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2'
TARGET = '2456ab782422af78135a2dd2c7e4d0cfaa23610d0057e48ee24db25bc774b874'
OUT.mkdir(exist_ok=False, parents=True)


def identity(p):
    return {'path': str(p), 'size': p.stat().st_size,
            'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}


def flatten(actions):
    for action in actions:
        yield action
        yield from flatten(action.children)


report = {'source': identity(SOURCE), 'script': identity(ROOT / 'tests/investigation/competitor_transport/replay_gravel.py'),
          'scope': 'exact captured compute shader and bound buffers only; no temporal or performance claim',
          'scan': [], 'exports': [], 'found': False}
capture = controller = None
(OUT / 'initialized.json').write_text(json.dumps(report, indent=2), encoding='utf-8')


def export(name, raw, selector):
    p = OUT / name
    p.write_bytes(bytes(raw))
    rec = dict(identity(p), selector=selector)
    report['exports'].append(rec)
    return rec


try:
    import renderdoc as rd
    assert report['source']['sha256'] == EXPECTED
    report['version'] = rd.GetVersionString()
    capture = rd.OpenCaptureFile()
    report['open'] = str(capture.OpenFile(str(SOURCE), '', None))
    status, controller = capture.OpenCapture(rd.ReplayOptions(), None)
    report['replay'] = str(status)
    assert controller is not None
    for action in flatten(controller.GetRootActions()):
        if not action.flags & rd.ActionFlags.Dispatch:
            continue
        # Simulation precedes the first main drawing chain in this capture.
        controller.SetFrameEvent(action.eventId, True)
        pipe = controller.GetPipelineState()
        stage = rd.ShaderStage.Compute
        reflection = pipe.GetShaderReflection(stage)
        if reflection is None:
            continue
        digest = hashlib.sha256(bytes(reflection.rawBytes)).hexdigest()
        report['scan'].append({'event': action.eventId, 'shader_sha256': digest})
        if len(report['scan']) % 20 == 0:
            (OUT / 'progress.json').write_text(json.dumps(report['scan'], indent=2), encoding='utf-8')
        if digest != TARGET:
            continue
        report['found'] = True
        report['event'] = action.eventId
        report['groups'] = list(action.dispatchDimension)
        report['threads'] = list(reflection.dispatchThreadsDimension)
        report['shader'] = str(pipe.GetShader(stage))
        report['constants'] = []
        report['bindings'] = []
        export('gravel_update.dxbc', reflection.rawBytes, f'test1 E{action.eventId} CS rawBytes')
        for i, block in enumerate(reflection.constantBlocks):
            bound = pipe.GetConstantBlock(stage, i, 0).descriptor
            size = min(bound.byteSize, block.byteSize)
            raw = controller.GetBufferData(bound.resource, bound.byteOffset, size)
            row = {'name': block.name, 'resource': str(bound.resource),
                   'offset': bound.byteOffset, 'bytes': size,
                   'raw': export('cb'+str(i)+'.raw', raw, f'CS constant block {i} offset {bound.byteOffset} size {size}')}
            report['constants'].append(row)
        for label, resources in [('readonly', pipe.GetReadOnlyResources(stage)),
                                 ('readwrite', pipe.GetReadWriteResources(stage))]:
            for used in resources:
                bound = used.descriptor
                row = {'access': label, 'index': used.access.index,
                       'resource': str(bound.resource), 'offset': bound.byteOffset,
                       'bytes': bound.byteSize, 'type': str(bound.type)}
                if 0 < bound.byteSize <= 16*1024*1024:
                    raw = controller.GetBufferData(bound.resource, bound.byteOffset, bound.byteSize)
                    row['raw'] = export(label+'_'+str(used.access.index)+'.raw', raw,
                                        f'test1 E{action.eventId} CS {label} descriptor index {used.access.index}, offset {bound.byteOffset}, size {bound.byteSize}')
                report['bindings'].append(row)
        break
    report['source_after'] = identity(SOURCE)
    report['source_unchanged'] = report['source_after'] == report['source']
except Exception:
    report['error'] = traceback.format_exc()
finally:
    if controller is not None:
        controller.Shutdown()
    if capture is not None:
        capture.Shutdown()
    (OUT / 'manifest.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
os._exit(0 if report.get('found') and report.get('source_unchanged') else 1)
