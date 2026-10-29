"""Join sparse timestamp spans to immutable audit snapshots and completions."""
from collections import Counter, defaultdict
import json
import math
from pathlib import Path
import re
import statistics
import struct
import sys


def stats(values):
    values = sorted(values)
    if not values:
        return None
    return {'n': len(values), 'mean': statistics.mean(values),
            **{f'p{p}': values[math.ceil(len(values)*p/100)-1] for p in (50,95,99)}}


def audit_classes(row):
    raw = bytes.fromhex(row['audit_hex'])
    result = []
    for slot in range(64):
        index, dt, accepted, s0, s1, cumulative, flags, unused = struct.unpack_from('<8I', raw, slot*32)
        result.append('fault' if flags else 'accepted' if accepted else 'rejected' if dt and s1 else 'invalid')
    return result


def analyze(directory):
    data = json.loads((directory/'capture.json').read_text(encoding='utf-8'))
    diagnostic = data['diagnostic']
    marks = {}
    duplicates = set()
    frame_mark_counts = Counter()
    for gpu in data['gpu']:
        for mark in gpu['marks']:
            if not mark['name'].startswith('m2_'):
                continue
            key = mark['name']
            frame_mark_counts[gpu['frame']] += 1
            if key in marks:
                duplicates.add(key)
            marks[key] = (gpu['frame'], mark['gpu_ns'])
    completions = {(e['detail']['state_seq'], e['detail']['tick']): e for e in data['timeline']['events']
                   if e['event'] == 'settle_end'}
    groups = defaultdict(list)
    cpus = defaultdict(list)
    tick_gpu = []
    tick_cpu = []
    drop = Counter()
    classes = Counter()
    attempts = Counter()
    valid = []
    sampled_slots = set()

    def interval(prefix):
        a, b = marks.get(prefix+'_start'), marks.get(prefix+'_end')
        if prefix+'_start' in duplicates or prefix+'_end' in duplicates:
            return None, 'duplicate_marker'
        if a is None or b is None:
            return None, 'missing_marker'
        if a[0] != b[0]:
            return None, 'cross_frame_pair'
        if b[1] < a[1]:
            return None, 'timestamp_regression'
        return {'timestamp_frame': a[0], 'start_ns': a[1], 'end_ns': b[1], 'ms': (b[1]-a[1])/1e6}, None

    for row in diagnostic['samples']:
        expected_seq = row['state_seq_before_seal'] + (row['control_flags'] == 0)
        identity = (expected_seq, row['sim_tick'])
        if identity not in completions:
            drop['completion_unmatched'] += 1
            continue
        if row['control_flags'] or row['status'] == 2:
            drop['fault_sample'] += 1
            continue
        classification = audit_classes(row)
        distribution = Counter(classification)
        if distribution['accepted'] != row['accepted_count'] or distribution['rejected'] != row['rejected_count'] or distribution['fault']:
            drop['audit_counts_conflict'] += 1
            continue
        prefix = f"m2_{row['sample_id']}_"
        total, error = interval(prefix+'tick')
        spans = []
        for span in row['spans']:
            observed, failure = interval(prefix+f"s{span['ordinal']}")
            if failure:
                error = failure
                break
            spans.append(span | observed)
        if error:
            drop[error] += 1
            continue
        if any(s['timestamp_frame'] != total['timestamp_frame'] for s in spans):
            drop['sample_cross_frame'] += 1
            continue
        kind = classification[row['slot']]
        classes[kind] += 1
        attempts.update(distribution)
        sampled_slots.add(row['slot'])
        cpu_by_ordinal = {s['ordinal']: s for s in row['cpu_spans']}
        for span in spans:
            group = kind if span['candidate_slot'] >= 0 else 'per_tick'
            label = f"{group}/{span['stage']}"
            groups[label].append(span['ms'])
            cpu = cpu_by_ordinal[span['ordinal']]
            cpus[label].append(cpu['end_us']-cpu['start_us'])
        tick_gpu.append(total['ms'])
        tick_cpu.append(row['cpu_end_us']-row['cpu_start_us'])
        valid.append({'sample_id':row['sample_id'], 'generation': row['generation'], 'record_seq':row['record_seq'],
                      'state_seq':expected_seq, 'sim_tick':row['sim_tick'], 'slot':row['slot'], 'class':kind,
                      'standard_cached':row['standard_cached'], 'accepted':row['accepted_count'],
                      'rejected':row['rejected_count'], 'invalid':row['invalid_slots'],
                      'actual_dt':row['actual_dt'], 'advanced_time_s':row['advanced_time_s'],
                      'capacity_exhausted':row['status']==1, 'whole_tick':total, 'spans':spans})
    wall = data['metadata']['intervals'][0]
    actual_sim = wall['end_sim_s']-wall['start_sim_s']
    result = {'valid_samples':len(valid), 'sampled_classes':dict(classes), 'audited_attempts':dict(attempts),
              'max_extra_marks_in_timestamp_frame':max(frame_mark_counts.values(),default=0),
              'slots_covered': sorted(sampled_slots), 'all_standard_cached': all(r['standard_cached'] for r in valid),
              'dropped_acquisition':diagnostic['dropped'], 'dropped_analysis':dict(drop),
              'pending':diagnostic['pending'], 'timeline_dropped':data['timeline']['dropped'],
              'gpu_ms': {k:stats(v) for k,v in groups.items()}, 'cpu_record_us':{k:stats(v) for k,v in cpus.items()},
              'whole_tick_gpu_ms':stats(tick_gpu), 'whole_tick_cpu_record_us':stats(tick_cpu),
              'sample_gpu_ms_per_sim_s':sum(tick_gpu)/sum(r['actual_dt'] for r in valid) if valid and sum(r['actual_dt'] for r in valid) else None,
              'completed_sim_s':actual_sim, 'wall_s':(wall['end_us']-wall['start_us'])/1e6,
              'samples':valid,
              'limits':['Sparse rotating slot, statistics split by accepted/rejected/invalid; absent coverage is unknown.',
                        'Control snapshot precedes work_seal; state_seq is joined against actual settle_end completion.',
                        'GPU timestamp intervals include scheduling effects; CPU/GPU clocks are never subtracted or added.',
                        'Whole-tick includes nested spans; stage spans must not be added again.',
                        'Diagnostic FPS is not normal-path performance.']}
    (directory/'diagnostic_analysis.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('samples','gpu_ms','cpu_record_us','limits')}))
    if not valid or not result['all_standard_cached'] or result['pending'] or result['timeline_dropped'] or result['max_extra_marks_in_timestamp_frame']>64:
        raise SystemExit(1)
    return result


if __name__ == '__main__':
    analyze(Path(sys.argv[1]))
