"""Small E1495 replay/readback matrix in RenderDoc embedded Python.

The E1490 post-state is a candidate input only, never a proven E1495 pre-state.
"""
import hashlib
import json
import os
import shutil
import traceback
from pathlib import Path

REQUEST = Path(os.environ['WATER_EVIDENCE_REQUEST'])
SCRIPT = Path(os.environ['WATER_EVIDENCE_SCRIPT'])
req = json.loads(REQUEST.read_text(encoding='utf-8'))
OUT = Path(req['output_root'])
OUT.mkdir(parents=True, exist_ok=False)
for name in ['raw', 'derived', 'sources', 'logs']:
    (OUT / name).mkdir()


def identity(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(8*1024*1024), b''):
            h.update(chunk)
    return dict(path=path.as_posix(), size_bytes=path.stat().st_size, sha256=h.hexdigest())


def write(name, data):
    (OUT / name).write_text(json.dumps(data, indent=2), encoding='utf-8')


report = dict(schema_version='1.0', run_id=req['run_id'], operation_status='failed', verification_status='not_evaluated',
    mode=req['repeat_mode'], samples=[], errors=[], pairing_kind='unproven', dependencies_complete=False,
    input_state_unknown=True, clocks=[], artifacts=[],
    limitations=['Post E1490 and post E1495 selections invoke separate replays. Same controller does not prove pairing.',
                 'Output differences without proven identical inputs are not a same-input nondeterminism measure.'])
cap = controller = None


def close_capture():
    global cap, controller
    if controller is not None:
        controller.Shutdown()
        controller = None
    if cap is not None:
        cap.Shutdown()
        cap = None


try:
    import renderdoc as rd
    source = Path(req['source']['source_path'])
    report['source'] = identity(source)
    if report['source']['sha256'] != req['source']['source_sha256']:
        raise ValueError('SOURCE_IDENTITY_MISMATCH')
    for path in [SCRIPT, REQUEST]:
        shutil.copyfile(path, OUT / 'sources' / path.name)
    report['tool'] = dict(version=rd.GetVersionString(), script=identity(SCRIPT))

    def open_capture():
        global cap, controller
        cap = rd.OpenCaptureFile()
        cap.OpenFile(str(source), '', None)
        status, controller = cap.OpenCapture(rd.ReplayOptions(), None)
        if controller is None:
            raise RuntimeError(str(status))

    def snapshot(sample, role, event):
        pipe = controller.GetPipelineState()
        stage = rd.ShaderStage.Compute
        reflection = pipe.GetShaderReflection(stage)
        shader_hash = hashlib.sha256(bytes(reflection.rawBytes)).hexdigest()
        expected = {1490: '9e5c7da8738200d374076a6cc3b48be52fdbad70e8c8dc2bd27eb75431d30523',
                    1495: '549114c23f1921610bacaf1d9ae375814fda1fb1de492cc2a4acfc53a502c64f'}
        if shader_hash != expected[event]:
            raise ValueError('SELECTOR_MISMATCH: shader')
        row = dict(event_id=event, boundary='post-dispatch', role=role, shader_sha256=shader_hash,
                   buffers=[], constants=[], pairing_kind='unproven')
        for used in pipe.GetReadWriteResources(stage):
            d = used.descriptor
            if str(d.resource) != 'ResourceId::139573' or d.byteOffset != 0 or d.byteSize != 2097152 or d.elementByteSize != 16:
                raise ValueError('SELECTOR_MISMATCH: binding')
            data = bytes(controller.GetBufferData(d.resource, d.byteOffset, d.byteSize))
            if len(data) != d.byteSize:
                raise ValueError('DEPENDENCY_MISSING: short water')
            path = OUT / ('raw/s%d_%s_water.bin' % (sample, role)); path.write_bytes(data)
            row['buffers'].append(dict(identity(path), resource=str(d.resource), byte_offset=d.byteOffset,
                                       byte_length=d.byteSize, stride=d.elementByteSize))
        if len(row['buffers']) != 1:
            raise ValueError('DEPENDENCY_MISSING: water')
        for index, block in enumerate(reflection.constantBlocks):
            d = pipe.GetConstantBlock(stage, index, 0).descriptor
            size = min(d.byteSize, block.byteSize)
            data = bytes(controller.GetBufferData(d.resource, d.byteOffset, size))
            if len(data) != size:
                raise ValueError('DEPENDENCY_MISSING: constants')
            path = OUT / ('raw/s%d_%s_cb%d.bin' % (sample, role, index)); path.write_bytes(data)
            row['constants'].append(dict(identity(path), resource=str(d.resource), byte_offset=d.byteOffset, byte_length=size))
        return row

    mode = req['repeat_mode']
    count = req['sample_count']
    if mode not in ['cached', 'force', 'fresh', 'process'] or count < 1:
        raise ValueError('SCHEMA_INVALID: repeat configuration')
    if mode != 'fresh':
        open_capture()
    prior_input = None
    for index in range(count):
        write('logs/progress.json', dict(phase='sample', mode=mode, index=index))
        if mode == 'fresh':
            open_capture()
        sample = dict(index=index, process_id=os.getpid(), replay_instance_id=req['replay_instance_id'],
                      controller_instance=index if mode == 'fresh' else 0,
                      force=mode != 'cached', pairing_kind='unproven', input_proven_identical=False)
        if mode != 'cached' or index == 0:
            controller.SetFrameEvent(1490, True)
            sample['candidate_input'] = snapshot(index, 'candidate_input', 1490)
            prior_input = sample['candidate_input']
            controller.SetFrameEvent(1495, True)
            sample['selection'] = 'force post E1490 read; force post E1495 read; different replay boundaries'
        else:
            sample['candidate_input'] = prior_input
            controller.SetFrameEvent(1495, False)
            sample['selection'] = 'same event with force=False; cached readback control, not a new execution'
        sample['output'] = snapshot(index, 'output', 1495)
        report['samples'].append(sample)
        write('manifest_partial.json', report)
        if mode == 'fresh':
            close_capture()
    report['source_after'] = identity(source)
    if report['source'] != report['source_after']:
        raise ValueError('SOURCE_CHANGED')
    report['operation_status'] = 'complete'
except Exception:
    report['errors'].append(dict(code='REPEAT_EXCEPTION', message=traceback.format_exc()))
finally:
    close_capture()
    report['artifacts'] = [identity(p) for p in OUT.rglob('*') if p.is_file()]
    write('manifest.json', report)
os._exit(0 if report['operation_status'] == 'complete' else 1)
