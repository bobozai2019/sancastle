"""Audit retained water bindings and full structured API span; no pairing claim."""
import argparse
import copy
import json
import re
import shutil
from pathlib import Path
from evidence_contract import identity

STAGES = {1484: ('floor', 0), 1490: ('velocity', 0), 1495: ('water', 0), 1500: ('advection', 0),
          1505: ('velocity', 1), 1510: ('water', 1), 1515: ('advection', 1),
          1520: ('velocity', 2), 1525: ('water', 2), 1530: ('advection', 2),
          1537: ('sources', 0), 1543: ('normal', 0)}
EXPECTED_WATER_PROGRAM = '549114c23f1921610bacaf1d9ae375814fda1fb1de492cc2a4acfc53a502c64f'


def write(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def plain(obj):
    if 'children' not in obj:
        return obj.get('custom_string') or obj.get('value')
    if obj['basetype'] == 'SDBasic.Array':
        return [plain(x) for x in obj['children']]
    return {child['name']: plain(child) for child in obj['children']}


def check_water(row, program=EXPECTED_WATER_PROGRAM, resource='ResourceId::139573'):
    errors = []
    if row['program']['sha256'] != program:
        errors.append('SELECTOR_MISMATCH:program')
    matches = [b for b in row['bindings'] if b['access'] == 'uav' and b['index'] == 0 and b['resource'] == resource]
    if len(matches) != 1 or matches[0]['byte_length'] != 2097152 or matches[0]['element_byte_size'] != 16:
        errors.append('SELECTOR_MISMATCH:binding')
    if row['groups'] != [16, 8, 1] or row['threads'] != [32, 32, 1]:
        errors.append('SELECTOR_MISMATCH:dispatch')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    out = args.output
    if not out.is_absolute() or not str(out).isascii():
        raise ValueError('Absolute ASCII output required')
    out.mkdir(parents=True, exist_ok=False)
    for directory in ['derived', 'sources', 'logs', 'raw']:
        (out / directory).mkdir()
    manifest = json.loads((args.input / 'manifest.json').read_text())
    calls = [json.loads(line) for line in (args.input / 'raw/api_calls.jsonl').read_text().splitlines()]
    chunks = json.loads((args.input / 'derived/chunk_inventory.json').read_text())
    event_map = {e['event_id']: e for e in json.loads((args.input / 'derived/api_event_map.json').read_text())}
    errors = []
    file_checks = []
    for artifact in manifest['file_inventory']:
        actual = identity(artifact['path'])
        matched = actual['sha256'] == artifact['sha256'] and actual['size_bytes'] == artifact['size_bytes']
        file_checks.append(dict(path=artifact['path'], matched=matched))
        if not matched:
            errors.append('ARTIFACT_CHANGED:' + artifact['path'])
    source_id = manifest['source']['sha256']
    stage_map = []
    raw_map = {}
    for row in manifest['events']:
        eid = row['event_id']
        stage, iteration = STAGES[eid]
        asm = Path(row['assembly']['path']).read_text()
        pipe = json.loads((args.input / ('derived/e%d_d3d12_pipeline.json' % eid)).read_text())
        declarations = [line.strip() for line in asm.splitlines() if 'dcl_' in line]
        counters = [b for b in row['bindings'] if b.get('raw', {}).get('size_bytes') != b.get('byte_length') and 'texture' not in b]
        if counters:
            errors.append('SHORT_BUFFER:E%d' % eid)
        if 'Swig Object' in json.dumps(pipe):
            errors.append('OPAQUE_PIPELINE:E%d' % eid)
        stage_map.append(dict(capture_sha256=source_id, event_id=eid, logical_stage=stage, iteration=iteration,
            shader_sha256=row['program']['sha256'], shader_resource=row['shader_resource'],
            threads=row['threads'], groups=row['groups'], boundary=row['boundary'], bindings=row['bindings'],
            constants=row['constants'], root_signature=pipe['rootSignature'], declarations=declarations,
            has_sampler_declaration=bool(re.search(r'\bdcl_sampler\b', asm)),
            has_shader_sync_instruction=bool(re.search(r'^\s*\d+:\s+sync', asm, re.M)),
            pairing_kind='unproven', dependency_complete_for_post_snapshot=not counters))
        raw_map[eid] = row
    water_errors = check_water(raw_map[1495]); errors.extend(water_errors)
    negatives = dict(correct=not water_errors,
                     wrong_program=check_water(raw_map[1495], program='0' * 64),
                     wrong_resource=check_water(raw_map[1495], resource='ResourceId::139571'))
    if not all([negatives['correct'], negatives['wrong_program'], negatives['wrong_resource']]):
        errors.append('NEGATIVE_CHECK_FAILED')
    write(out / 'derived/selector_checks.json', negatives)
    write(out / 'derived/stage_map.json', stage_map)
    decoded = {c['chunk_index']: dict(chunk_index=c['chunk_index'], name=c['name'], params=plain(c)) for c in calls}
    first, last = event_map[1484]['chunk_index'], event_map[1543]['chunk_index']
    span = list(range(first, last + 1))
    missing = [index for index in span if index not in decoded]
    if missing:
        errors.append('API_SPAN_MISSING')
    graph = []
    previous = first - 1
    for eid in STAGES:
        end = event_map[eid]['chunk_index']
        dispatch = decoded[end]
        command_list = dispatch['params']['pCommandList']
        barriers = [c for i, c in decoded.items() if previous < i < end and 'Barrier' in c['name'] and c['params'].get('pCommandList') == command_list]
        # The floor's immediately preceding transition block lies before its dispatch.
        if eid == 1484:
            barriers = [c for i,c in decoded.items() if end-8 <= i < end and 'Barrier' in c['name'] and c['params'].get('pCommandList') == command_list]
        graph.append(dict(event_id=eid, dispatch_chunk=end, command_list=command_list,
                          preceding_barriers=barriers, dependent_resources=[b['resource'] for b in raw_map[eid]['bindings']]))
        previous = end
    queues = [c for c in decoded.values() if 'CommandQueue::' in c['name']]
    queue_inventory = [c for c in chunks if 'CommandQueue::' in c['name'] or 'Fence::' in c['name']]
    queue_gaps = [c for c in queue_inventory if c['index'] not in decoded]
    for c in graph:
        if c['command_list'] != 'ResourceId::3703':
            errors.append('COMMAND_LIST_MISMATCH')
        if not c['preceding_barriers']:
            errors.append('BARRIER_MISSING:E%d' % c['event_id'])
    if queue_gaps:
        errors.append('QUEUE_API_MISSING')
    write(out / 'derived/sync_graph.json', dict(source_capture_sha256=source_id, nodes=graph, queues=queues,
          relevant_span=[first, last], missing_chunks=missing, queue_inventory=queue_inventory, queue_gaps=queue_gaps,
          interpretation='Chunk order is serialization/recording order; event IDs identify replay execution. Do not turn chunk order into CPU/GPU time.',
          limitations=['Capture-bound API scope; no global lifecycle guarantee', 'UAV barriers between kernels do not define thread ordering inside a kernel']))
    write(out / 'derived/file_checks.json', file_checks)
    write(out / 'derived/source_copy_check.json', dict(primary=identity('D:/godot/project/sandcastle/sandcastlegame/test1.rdc'),
                                                     copy=identity('D:/godot/project/sandcastle/rdc/test1.rdc')))
    shutil.copyfile(__file__, out / 'sources/audit_pilot.py')
    shutil.copyfile(Path(__file__).with_name('evidence_contract.py'), out / 'sources/evidence_contract.py')
    write(out / 'manifest.json', dict(operation_status='complete', verification_status='failed' if errors else 'passed',
        input_manifest=identity(args.input / 'manifest.json'), errors=errors, method='T01 static audit of actual replay exports',
        scope='G1 program/binding/synchronization/post-snapshot completeness only; not reliable input/output pairing',
        artifacts=[identity(p) for p in out.rglob('*') if p.is_file()], pairing_kind='unproven'))
    print(json.dumps(dict(output=out.as_posix(), stages=len(stage_map), checked_files=len(file_checks), errors=errors)))
    raise SystemExit(1 if errors else 0)


if __name__ == '__main__':
    main()
