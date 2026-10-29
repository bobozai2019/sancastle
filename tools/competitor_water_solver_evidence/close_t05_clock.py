"""Close scoped T05 evidence and write explicit CPU/simulation/GPU clock boundaries."""
import argparse
import collections
import json
import shutil
from pathlib import Path
from evidence_contract import identity
from audit_runtime_pilot import water_events, property_value, closure


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', required=True, type=Path)
    args = ap.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    base = out.parent
    errors, evidence = [], []
    required = [
        ('natural_observer_decision', 't05_d07_freeze_20261025_v1', 'decision.json'),
        ('controlled_observer_decision', 't05_d07_control_freeze_20261025_v1', 'decision.json'),
        ('natural_window', 't05_formal_natural_audit_20261025_v5', 'trajectory.json'),
        ('controlled_window', 't05_control_formal_window_audit_20261025_v1', 'trajectory.json'),
        ('controlled_actions', 't05_control_formal_phase_audit_20261025_v1', 'control_audit.json'),
        ('natural_gpu_consumption', 't05_consumption_20261025_v4', 'consumption.json'),
        ('controlled_gpu_consumption', 't05_consumption_20261025_v5', 'consumption.json'),
    ]
    reports = {}
    for role, run, name in required:
        folder = base / run
        data = json.loads((folder / name).read_text())
        if data.get('verification_status') != 'passed' or data.get('errors'):
            errors.append(role + ':NOT_PASSED')
        manifest = json.loads((folder / 'manifest.json').read_text())
        for item in manifest['artifacts']:
            actual = identity(item['path'])
            if actual['sha256'] != item['sha256'] or actual['size_bytes'] != item['size_bytes']:
                errors.append(role + ':IDENTITY_CHANGED')
        reports[role] = data
        evidence.append(dict(role=role, **identity(folder / name)))
    traces = []
    for label, run, window_role, clock_run in [
        ('natural', 't05_formal_natural_20261025_v5', 'natural_window', 't05_formal_clock_audit_20261025_v2'),
        ('controlled', 't05_control_formal_20261025_v1', 'controlled_window', 't05_control_formal_clock_audit_20261025_v1'),
    ]:
        folder = base / run
        raw = json.loads((folder / 'logs/events.json').read_text())
        events = water_events(raw)
        stats = json.loads((folder / 'observer_final.json').read_text())
        if closure(events, stats):
            errors.append(label + ':TRACE_NOT_CLOSED')
        report = json.loads((base / clock_run / (run + '.json')).read_text())
        if report['errors'] or report['artifact_identity_errors'] or report['accumulation_summary']['floor_count_mismatches']:
            errors.append(label + ':CLOCK_MAPPING_ERROR')
        source_calls = [e for e in events if e['kind'] == 'dispatch_enter' and e['kernel_name'] == 'UpdateAmount']
        clocks = [e for e in events if e['kind'] == 'engine_clock_sample']
        if collections.Counter(e['call_id'] for e in source_calls) != collections.Counter(e['call_id'] for e in clocks):
            errors.append(label + ':PER_SOURCE_CLOCK_MISSING')
        if report['accumulation_summary']['source_calls'] != len(source_calls) or len(report['clock_samples']) != len(clocks):
            errors.append(label + ':AUDIT_SCOPE_MISMATCH')
        if not all(p['dt_matches'] and p['time_matches'] and p['frame_matches'] and p['fixed_time_matches'] for p in report['clock_samples']):
            errors.append(label + ':CLOCK_FIELDS_NOT_CORRESPONDING')
        window = reports[window_role]
        low, high = map(int, window['window_qpc'])
        freq = window['qpc_frequency']
        lookup = {e['call_id']: e for e in source_calls}
        actions = reports['controlled_actions']['actions'] if label == 'controlled' else []
        phases = [(low, 1)] + [(int(e['qpc']) + freq, e['requested_scale']) for e in actions]
        mapped = []
        for index, (start, scale) in enumerate(phases):
            end = min(high, int(actions[index]['begin_qpc']) - freq) if index < len(actions) else high
            start = max(start, low)
            samples = [e for e in clocks if start <= int(e['qpc']) <= end]
            if len(samples) < 10:
                errors.append(label + ':PHASE_TOO_SHORT:' + str(index))
                continue
            if {e['values']['get_timeScale'] for e in samples} != {scale}:
                errors.append(label + ':PHASE_SCALE_MISMATCH:' + str(index))
            first, last = samples[0], samples[-1]
            elapsed = (int(last['qpc']) - int(first['qpc'])) / freq
            fixed_delta = last['values']['get_fixedTime'] - first['values']['get_fixedTime']
            play = [property_value(lookup[e['call_id']], 'playTime', 'global_parameters') for e in samples]
            frames = [property_value(lookup[e['call_id']], 'frameCount', 'global_parameters') for e in samples]
            mapped.append(dict(phase_index=index, scale=scale, bounds_qpc=[str(start), str(end)],
                               first_call_id=first['call_id'], last_call_id=last['call_id'], samples=len(samples),
                               cpu_qpc_elapsed_seconds=elapsed, fixed_time_delta_seconds=fixed_delta,
                               playTime_delta=play[-1]-play[0], fixed_time_per_qpc_second=fixed_delta/elapsed,
                               playTime_per_qpc_second=(play[-1]-play[0])/elapsed,
                               native_unscaledDeltaTime_values=sorted({e['values']['get_unscaledDeltaTime'] for e in samples}),
                               adjacent_same_frame_and_playTime=sum(a==b and pa==pb for a,b,pa,pb in zip(frames,frames[1:],play,play[1:])),
                               interpretation='Observed CPU endpoint ratios only; frame catch-up and f32 reading precision are retained, not corrected into an observer-free frequency.'))
        manifest = json.loads((folder / 'manifest.json').read_text())
        if manifest['operation_status'] != 'complete' or not manifest['watched_source_and_user_data_unchanged']:
            errors.append(label + ':RUN_NOT_CLOSED')
        # A green derived report cannot replace checking the underlying immutable run.
        for item in manifest['artifacts']:
            actual = identity(item['path'])
            if actual['sha256'] != item['sha256'] or actual['size_bytes'] != item['size_bytes']:
                errors.append(label + ':RUNTIME_IDENTITY_CHANGED')
        traces.append(dict(mode=label, runtime=identity(folder / 'manifest.json'),
                           qpc_frequency=freq, epoch_qpc=window['epoch_qpc'], formal_window_qpc=window['window_qpc'],
                           cpu_dispatches=stats['dispatches'], source_calls=len(source_calls), clock_samples=len(clocks),
                           formal_source_calls=window['window_source_count'], phases=mapped,
                           integration=report['accumulation_summary'], observed_clock_fields=report['observed_values'],
                           clock_audit=identity(base / clock_run / (run + '.json'))))
    result = dict(operation_status='complete', verification_status='passed' if not errors else 'failed',
                  scope='T05/G4 selected natural no-edit state and explicit held public-engine 1/.5/1 time input, on current isolated 512x512 runtime. No original UI/paused state, unique playTime formula, observer-free cadence, GPU execution timing or 512x256 numeric-budget extension.',
                  evidence=evidence, traces=traces, errors=errors,
                  clock_mapping=dict(
                      cpu_qpc=dict(unit='seconds after division by actual frequency', meaning='CPU native API observation brackets; per-process instance/epoch, never GPU completion'),
                      source_dt=dict(value=0.02500000037252903, unit='configured simulation seconds per source call', evidence='Native fixed-step context and actual source CB at captured program; persists at controlled half scale'),
                      integration_dt=dict(value=0.00732421875, unit='configured integration substep seconds', evidence='Original GPU CB plus CPU parameter snapshots; prefix round count floor(N*source_dt/integration_dt) observed, unique scheduler implementation unknown'),
                      playTime=dict(unit='Shader global scalar, advancing with the observed scaled simulation clock', evidence='Per-source effective global property plus captured CB113.z; endpoint mapping in traces', formula=None, formula_confidence='C0', gpu_correspondence_confidence='C2', caveat='Not equal to fixedTime and may repeat for multiple source calls in one frame; do not replace it by a fixed tick counter'),
                      gpu_timestamp=None, gpu_frequency=None, gpu_qpc_calibration=None,
                      gpu_timing_reason='No timestamp query measured in this runtime experiment; CPU Dispatch return and Present do not establish GPU completion.'),
                  unresolved=['CPU origin of GPU light_factor=1', 'Original playTime and waveAmplitude generation formulas',
                              'Original UI control bindings and pause/reset lifecycle', 'Unobserved parameter/state/hardware range',
                              'GPU execution timing and uninstrumented wall-clock cadence'],
                  gate='G4 scoped evidence passed' if not errors else 'G4 not passed')
    for name in ['close_t05_clock.py','audit_runtime_pilot.py','evidence_contract.py']:
        shutil.copyfile(Path(__file__).parent / name, out / name)
    (out / 'clock_mapping.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    (out / 'manifest.json').write_text(json.dumps(dict(operation_status='complete', verification_status=result['verification_status'], errors=errors, artifacts=[identity(p) for p in out.iterdir() if p.is_file()]), indent=2), encoding='utf-8')
    print(json.dumps(dict(status=result['verification_status'], errors=errors, phases=[dict(mode=t['mode'], phases=t['phases']) for t in traces])))
    raise SystemExit(bool(errors))


if __name__ == '__main__':
    main()
