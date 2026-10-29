"""Audit explicit public Time intervention and phase observations; not original UI behavior."""
import argparse
import copy
import json
import shutil
from pathlib import Path
from audit_runtime_pilot import water_events, closure, property_value
from evidence_contract import identity


def control_errors(events, stats, request):
    errors = []
    if [e['seq'] for e in events] != list(range(1, stats['last_seq'] + 1)):
        errors.append('CONTROL_SEQUENCE_NOT_CLOSED')
    if stats['errors'] or not stats['installed'] or not stats['armed']:
        errors.append('CONTROL_NOT_READY_OR_ERROR')
    actions = [e for e in events if e['kind'] == 'control_action']
    if len(actions) != len(request['actions']) or stats['actions'] != len(actions):
        errors.append('CONTROL_ACTION_COUNT_MISMATCH')
    for index, (actual, expected) in enumerate(zip(actions, request['actions'])):
        if actual['action_index'] != index or actual['scheduled_seconds'] != expected['at_seconds'] or actual['requested_scale'] != expected['scale'] or actual['readback_scale'] != expected['scale']:
            errors.append('CONTROL_ACTION_MISMATCH')
        if not actual['in_fixed_step'] or actual['elapsed_seconds'] < expected['at_seconds']:
            errors.append('CONTROL_ACTION_CONTEXT_OR_TIME')
    reassertions = [e for e in events if e['kind'] == 'control_reassert']
    if len(reassertions) != stats.get('reassertions', 0):
        errors.append('REASSERT_COUNT_MISMATCH')
    if any(e['requested_scale'] != e['readback_scale'] for e in reassertions):
        errors.append('REASSERT_READBACK_MISMATCH')
    if request.get('hold_scale') and any(a['scale'] == .5 for a in request['actions']) and not reassertions:
        errors.append('HELD_CONTROL_NOT_WITNESSED')
    return errors


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--run', required=True, type=Path)
    ap.add_argument('--output', required=True, type=Path)
    args = ap.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    for name in ['audit_clock_control.py', 'audit_runtime_pilot.py', 'evidence_contract.py']:
        shutil.copyfile(Path(__file__).parent / name, out / name)
    raw = json.loads((args.run / 'logs/events.json').read_text())
    request = json.loads((args.run / 'control_request.json').read_text())
    stats = json.loads((args.run / 'control_final.json').read_text())
    mode = json.loads((args.run / 'mode.json').read_text())
    control = [r['payload']['event'] for r in raw if r.get('payload', {}).get('kind') == 'clock_control']
    errors = control_errors(control, stats, request)
    water = water_events(raw)
    water_stats = json.loads((args.run / 'observer_final.json').read_text())
    water_errors = closure(water, water_stats)
    diagnostic = bool(mode.get('hook_schedule'))
    if water_errors != (['DIAGNOSTIC_TRACE_GAP'] if diagnostic else []):
        errors.append('WATER_CLOSURE:' + str(water_errors))
    frequency = int(next(e['qpc_frequency'] for e in control if e['kind'] == 'control_loaded'))
    epoch = int(next(e['epoch_qpc'] for e in control if e['kind'] == 'control_arm'))
    actions = [e for e in control if e['kind'] == 'control_action']
    calls = {e['call_id']: e for e in water if e['kind'] == 'dispatch_enter'}
    clocks = [e for e in water if e['kind'] == 'engine_clock_sample']
    phases = []
    # Exclude a one-second bracket around each intervention; retain all raw samples.
    boundaries = [(epoch + 9 * frequency, 1)] + [(int(e['qpc']) + frequency, e['requested_scale']) for e in actions]
    for index, (low, scale) in enumerate(boundaries):
        high = int(actions[index]['begin_qpc']) - frequency if index < len(actions) else (int(clocks[-1]['qpc']) if clocks else low)
        samples = [e for e in clocks if low <= int(e['qpc']) <= high]
        values = {name: sorted({e['values'].get(name) for e in samples}, key=str) for name in ['get_timeScale', 'get_fixedDeltaTime', 'get_deltaTime', 'get_unscaledDeltaTime', 'get_inFixedTimeStep']}
        if samples and values['get_timeScale'] != [scale]:
            errors.append('PHASE_SCALE_NOT_HELD:' + str(index))
        if not diagnostic and request.get('hold_scale') and index > 0 and len(samples) < 10:
            errors.append('CONTROL_PHASE_INSUFFICIENT:' + str(index))
        rate = None
        if len(samples) > 1:
            first, last = samples[0], samples[-1]
            wall = (int(last['qpc']) - int(first['qpc'])) / frequency
            delta = lambda name: last['values'][name] - first['values'][name]
            play = lambda e: property_value(calls[e['call_id']], 'playTime', 'global_parameters')
            rate = dict(cpu_qpc_seconds=wall, source_intervals=len(samples)-1,
                        native_fixed_time_delta=delta('get_fixedTime'), native_unscaled_time_delta=delta('get_unscaledTime'),
                        shader_playTime_delta=play(last)-play(first),
                        fixed_time_per_qpc_second=delta('get_fixedTime')/wall,
                        playTime_per_qpc_second=(play(last)-play(first))/wall)
        phases.append(dict(index=index, expected_scale=scale, qpc_bounds=[str(low), str(high)],
                           native_clock_count=len(samples), observed=values, rate=rate,
                           continuous=not diagnostic))
    negatives = []
    if actions:
        bad = copy.deepcopy(control)
        next(e for e in bad if e['kind'] == 'control_action')['readback_scale'] = .75
        negatives.append(dict(case='corrupt_action_readback', rejected='CONTROL_ACTION_MISMATCH' in control_errors(bad, stats, request)))
        bad = [e for e in control if e is not actions[-1]]
        negatives.append(dict(case='missing_restore_action', rejected='CONTROL_ACTION_COUNT_MISMATCH' in control_errors(bad, stats, request)))
        bad = copy.deepcopy(control)
        next(e for e in bad if e['kind'] == 'control_action')['in_fixed_step'] = False
        negatives.append(dict(case='nonfixed_control_thread', rejected='CONTROL_ACTION_CONTEXT_OR_TIME' in control_errors(bad, stats, request)))
        if not all(e['rejected'] for e in negatives):
            errors.append('CONTROL_NEGATIVE_NOT_REJECTED')
    manifest = json.loads((args.run / 'manifest.json').read_text())
    fingerprint = []
    for expected in manifest['artifacts']:
        actual = identity(expected['path'])
        if actual['sha256'] != expected['sha256'] or actual['size_bytes'] != expected['size_bytes']:
            fingerprint.append(expected['path'])
    if fingerprint or manifest['operation_status'] != 'complete' or not manifest['watched_source_and_user_data_unchanged']:
        errors.append('RUN_OR_ARTIFACT_NOT_CLOSED')
    report = dict(operation_status='complete', verification_status='passed' if not errors else 'failed',
                  scope='Explicit public engine Time input and sampled phase observations. Diagnostic hook gaps remain unusable as continuous trajectories. No original UI/control formula or GPU completion claim.',
                  runtime=identity(args.run / 'manifest.json'), request=identity(args.run / 'control_request.json'),
                  stats=stats, actions=actions, phases=phases, diagnostic=diagnostic,
                  clock_samples=len(clocks), negatives=negatives, artifact_identity_errors=fingerprint, errors=errors,
                  initial_coverage='Sidecar and water observer install sequentially; counts before full water coverage can differ. Action/source pairing uses QPC and actual per-dispatch clock samples, not equality of global source indices.')
    (out / 'control_audit.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    (out / 'manifest.json').write_text(json.dumps(dict(operation_status='complete', verification_status=report['verification_status'], errors=errors, artifacts=[identity(p) for p in out.iterdir() if p.is_file()]), indent=2), encoding='utf-8')
    print(json.dumps(dict(status=report['verification_status'], actions=len(actions), phases=[dict(scale=p['expected_scale'], count=p['native_clock_count']) for p in phases], errors=errors)))
    raise SystemExit(bool(errors))


if __name__ == '__main__':
    main()
