"""RenderDoc 1.46 embedded Python pilot. WATER_EVIDENCE_REQUEST is validated first.

Launch: qrenderdoc.exe --python <this absolute path>. Never modifies the capture.
Uses public structured-file API (v1.46 structured_data.h) for complete call records.
"""
import hashlib
import json
import os
import shutil
import struct
import traceback
from pathlib import Path

REQUEST = Path(os.environ['WATER_EVIDENCE_REQUEST'])
SCRIPT = Path(os.environ['WATER_EVIDENCE_SCRIPT'])
req = json.loads(REQUEST.read_text(encoding='utf-8'))
OUT = Path(req['output_root'])
if not OUT.is_absolute() or not str(OUT).isascii():
    raise ValueError('Absolute ASCII output required')
OUT.mkdir(parents=True, exist_ok=False)
for directory in ['raw', 'derived', 'sources', 'logs']:
    (OUT / directory).mkdir()


def identity(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b''):
            digest.update(chunk)
    return dict(path=path.as_posix(), size_bytes=path.stat().st_size, sha256=digest.hexdigest())


def write(name, data):
    (OUT / name).write_text(json.dumps(data, ensure_ascii=True, indent=2), encoding='utf-8')


report = dict(schema_version='1.0', run_id=req['run_id'], operation_status='failed',
              verification_status='not_evaluated', artifacts=[], errors=[], dependencies_complete=False,
              pairing=dict(pairing_kind='unproven', method='Public post-event selections; no dispatch-enclosing copy',
                           proof_artifact_ids=[], execution_instance_id=req['replay_instance_id']),
              clocks=[], observations=[], unknowns=[], events=[])


def save(name, data, kind, selector):
    path = OUT / name
    path.write_bytes(bytes(data))
    item = dict(identity(path), artifact_id=name, kind=kind, selector=selector,
                source_ids=[req['source']['source_id']], parent_artifact_ids=[], completeness='complete')
    report['artifacts'].append(item)
    return item


cap = controller = None
try:
    import renderdoc as rd
    source = Path(req['source']['source_path'])
    report['source'] = identity(source)
    if report['source']['sha256'] != req['source']['source_sha256'] or report['source']['size_bytes'] != req['source']['source_size']:
        raise ValueError('SOURCE_IDENTITY_MISMATCH')
    for path in [SCRIPT, REQUEST]:
        shutil.copyfile(path, OUT / 'sources' / path.name)
    report['tool'] = dict(version=rd.GetVersionString(), script=identity(SCRIPT),
                          executable=identity(Path('D:/other_software/RenderDoc/qrenderdoc.exe')),
                          command='qrenderdoc.exe --python ' + str(SCRIPT), request=identity(REQUEST))
    write('logs/progress.json', dict(phase='open_capture'))
    cap = rd.OpenCaptureFile()
    report['open_file'] = str(cap.OpenFile(str(source), '', None))
    status, controller = cap.OpenCapture(rd.ReplayOptions(), None)
    report['open_capture'] = str(status)
    if controller is None:
        raise RuntimeError(str(status))
    sf = controller.GetStructuredFile()
    report['api'] = str(controller.GetAPIProperties().pipelineType)
    actions = {}
    api_events = {}

    def walk(items):
        for action in items:
            actions[action.eventId] = action
            for event in action.events:
                api_events[event.eventId] = dict(event_id=event.eventId, chunk_index=event.chunkIndex, file_offset=event.fileOffset)
            walk(action.children)
    walk(controller.GetRootActions())
    write('derived/action_events.json', [dict(event_id=a.eventId, name=a.GetName(sf),
         flags=str(a.flags), groups=list(a.dispatchDimension), api_events=[e.eventId for e in a.events]) for a in actions.values()])
    write('derived/api_event_map.json', list(api_events.values()))
    write('derived/chunk_inventory.json', [dict(index=i, name=c.name, chunk_id=c.metadata.chunkID,
         flags=str(c.metadata.flags), length=c.metadata.length) for i, c in enumerate(sf.chunks)])

    def sd_object(obj):
        result = dict(name=obj.name, type=obj.type.name, basetype=str(obj.type.basetype), flags=str(obj.type.flags), byte_size=obj.type.byteSize)
        t = obj.type.basetype
        if t in [rd.SDBasic.Chunk, rd.SDBasic.Struct, rd.SDBasic.Array]:
            result['children'] = [sd_object(obj.GetChild(i)) for i in range(obj.NumChildren())]
        elif t == rd.SDBasic.String:
            result['value'] = obj.data.string
        elif t == rd.SDBasic.Resource:
            result['value'] = str(obj.data.basic.id)
        elif t == rd.SDBasic.Float:
            result['value'] = obj.data.basic.d
        elif t == rd.SDBasic.Boolean:
            result['value'] = obj.data.basic.b
        elif t == rd.SDBasic.SignedInteger:
            result['value'] = obj.data.basic.i
        elif t == rd.SDBasic.Character:
            result['value'] = str(obj.data.basic.c)
        elif t != rd.SDBasic.Null:
            result['value'] = obj.data.basic.u
            result['custom_string'] = obj.data.string
        return result

    # All structured call names retained. Fully decode water span and all queue,
    # command-list lifecycle, fences, barriers and aliasing calls across frame.
    selected_chunks = set(e['chunk_index'] for eid, e in api_events.items() if 1460 <= eid <= 1550)
    # Event lists omit calls that have no event (e.g. descriptor writes). Retain
    # the entire contiguous chunk span, not only chunks with an API event ID.
    if selected_chunks:
        selected_chunks.update(range(min(selected_chunks), max(selected_chunks) + 1))
    for i, c in enumerate(sf.chunks):
        if any(x in c.name for x in ['ResourceBarrier', 'Barrier', 'ExecuteCommandLists', 'Signal', 'Wait', 'CommandList::Reset', 'CommandList::Close', 'CommandQueue::']):
            selected_chunks.add(i)
    write('logs/progress.json', dict(phase='structured_calls', count=len(selected_chunks)))
    with (OUT / 'raw/api_calls.jsonl').open('w', encoding='utf-8') as stream:
        for i in sorted(selected_chunks):
            c = sf.chunks[i]
            data = sd_object(c)
            data.update(chunk_index=i, chunk_id=c.metadata.chunkID, flags=str(c.metadata.flags),
                        length=c.metadata.length, thread_id=c.metadata.threadID,
                        timestamp_micro=c.metadata.timestampMicro, duration_micro=c.metadata.durationMicro)
            stream.write(json.dumps(data, ensure_ascii=True) + '\n')
    buffers = {b.resourceId: b for b in controller.GetBuffers()}
    textures = {t.resourceId: t for t in controller.GetTextures()}
    stage = rd.ShaderStage.Compute
    def public_fields(obj):
        if obj is None or isinstance(obj, (bool, int, float, str)):
            return obj
        if isinstance(obj, (bytes, bytearray)):
            return dict(bytes=len(obj), sha256=hashlib.sha256(obj).hexdigest())
        if isinstance(obj, (list, tuple)):
            return [public_fields(x) for x in obj]
        if isinstance(obj, rd.ResourceId):
            return str(obj)
        if hasattr(obj, '__len__') and hasattr(obj, '__getitem__'):
            return [public_fields(x) for x in obj]
        result = {}
        for field in dir(obj):
            if field.startswith('_') or field in ['this', 'thisown', 'reflection']:
                continue
            value = getattr(obj, field)
            if not callable(value):
                result[field] = public_fields(value)
        return result if result else str(obj)

    write('derived/api_properties.json', public_fields(controller.GetAPIProperties()))
    selectors = req.get('events', [1495])
    for eid in selectors:
        write('logs/progress.json', dict(phase='post_event', event=eid))
        controller.SetFrameEvent(eid, True)
        pipe = controller.GetPipelineState()
        refl = pipe.GetShaderReflection(stage)
        if refl is None:
            raise ValueError('SELECTOR_MISMATCH: no compute shader at E%d' % eid)
        prefix = 'raw/e%d' % eid
        row = dict(event_id=eid, boundary='post-dispatch', groups=list(actions[eid].dispatchDimension),
                   threads=list(refl.dispatchThreadsDimension), shader_resource=str(pipe.GetShader(stage)),
                   bindings=[], constants=[], samplers=[], reflection_readonly=[r.name for r in refl.readOnlyResources],
                   reflection_readwrite=[r.name for r in refl.readWriteResources])
        report['events'].append(row)
        write('derived/e%d_d3d12_pipeline.json' % eid, public_fields(controller.GetD3D12PipelineState()))
        row['program'] = save(prefix + '.dxbc', refl.rawBytes, 'program', dict(event_id=eid, stage='compute'))
        row['assembly'] = save(prefix + '.asm', controller.DisassembleShader(pipe.GetComputePipelineObject(), refl, '').encode('utf-8'), 'decoded', dict(event_id=eid))
        if eid == req['selector']['event_id'] and req['selector'].get('shader_sha256') and row['program']['sha256'] != req['selector']['shader_sha256']:
            raise ValueError('SELECTOR_MISMATCH: shader')
        for index, block in enumerate(refl.constantBlocks):
            d = pipe.GetConstantBlock(stage, index, 0).descriptor
            size = min(d.byteSize, block.byteSize)
            raw = bytes(controller.GetBufferData(d.resource, d.byteOffset, size))
            if len(raw) != size or size <= 0:
                raise ValueError('DEPENDENCY_MISSING: constants')
            row['constants'].append(dict(index=index, name=block.name, resource=str(d.resource), byte_offset=d.byteOffset,
                byte_length=size, raw=save(prefix + '_cb%d.bin' % index, raw, 'raw_snapshot', dict(event_id=eid, resource=str(d.resource), byte_offset=d.byteOffset, byte_length=size)),
                float4=[list(struct.unpack_from('<4f', raw, n)) for n in range(0, size-15, 16)]))
        for access, used_list in [('srv', pipe.GetReadOnlyResources(stage)), ('uav', pipe.GetReadWriteResources(stage))]:
            for used in used_list:
                d = used.descriptor
                selector = dict(event_id=eid, resource=str(d.resource), access=access, index=used.access.index,
                     byte_offset=d.byteOffset, byte_length=d.byteSize, descriptor_type=str(d.type),
                     format=d.format.Name(), element_byte_size=d.elementByteSize)
                row['bindings'].append(selector)
                name = prefix + '_%s%d.bin' % (access, used.access.index)
                if d.resource in buffers:
                    size = d.byteSize
                    if size <= 0 or size > buffers[d.resource].length:
                        raise ValueError('DEPENDENCY_MISSING: invalid buffer extent')
                    data = bytes(controller.GetBufferData(d.resource, d.byteOffset, size))
                    if len(data) != size:
                        raise ValueError('DEPENDENCY_MISSING: short buffer')
                    selector['buffer_bytes'] = buffers[d.resource].length
                    selector['raw'] = save(name, data, 'raw_snapshot', dict(selector))
                elif d.resource in textures:
                    t = textures[d.resource]
                    selector['texture'] = dict(width=t.width, height=t.height, depth=t.depth, mips=t.mips, array_size=t.arraysize, format=t.format.Name())
                    selector['raw'] = save(name, controller.GetTextureData(d.resource, rd.Subresource()), 'raw_snapshot', dict(selector, mip=0, array_slice=0, sample=0))
                else:
                    report['errors'].append(dict(code='DEPENDENCY_MISSING', selector=selector, message='Resource not buffer or texture'))
        write('manifest_partial.json', report)
    report['source_after'] = identity(source)
    if report['source'] != report['source_after']:
        raise ValueError('SOURCE_CHANGED')
    report['operation_status'] = 'partial' if report['errors'] else 'complete'
    report['unknowns'] = ['Pairing unproven; no original dispatch pre-state is supplied by a post-event selection',
                          'Descriptor views and synchronization require offline audit of retained API calls',
                          'No numeric equivalence or runtime clock claim']
except Exception:
    report['errors'].append(dict(code='PILOT_EXCEPTION', message=traceback.format_exc(), selector=req.get('selector'),
                                artifact_refs=[], retry_condition='Diagnose API compatibility and create new run'))
finally:
    if controller is not None:
        controller.Shutdown()
    if cap is not None:
        cap.Shutdown()
    report['file_inventory'] = [identity(p) for p in OUT.rglob('*') if p.is_file() and p.name != 'manifest.json']
    write('manifest.json', report)
os._exit(0 if report['operation_status'] == 'complete' else 1)

