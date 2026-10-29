"""Validate one no-input D07 trajectory; this does not accept controllable input or G4."""
import argparse
import collections
import json
import shutil
from pathlib import Path
from audit_runtime_pilot import water_events, closure, property_value
from audit_runtime_modes import metrics
from evidence_contract import identity


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--run', required=True, type=Path)
    ap.add_argument('--decision', required=True, type=Path)
    ap.add_argument('--output', required=True, type=Path)
    args = ap.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    for name in ['audit_formal_trajectory.py', 'audit_runtime_pilot.py', 'audit_runtime_modes.py', 'evidence_contract.py']:
        shutil.copyfile(Path(__file__).parent / name, out / name)
    decision = json.loads(args.decision.read_text())
    criteria_path = args.decision.parent / 'criteria.json'
    if not criteria_path.exists():
        criteria_path = args.decision.parent / 'criteria_scale1.json'
    criteria = json.loads(criteria_path.read_text())
    cfg, rec = criteria['calibration'], criteria['recording']
    raw = json.loads((args.run / 'logs/events.json').read_text())
    mode = json.loads((args.run / 'mode.json').read_text())
    manifest = json.loads((args.run / 'manifest.json').read_text())
    stats = json.loads((args.run / 'observer_final.json').read_text())
    ps = json.loads((args.run / 'presentation_final.json').read_text())
    water = water_events(raw)
    errors = closure(water, stats)
    if decision.get('decision_status') != 'accepted':
        errors.append('D07_NOT_ACCEPTED')
    controlled = bool(rec.get('public_time_control'))
    eligible = mode.get('formal_eligible') or (controlled and mode.get('control_experiment') and not mode.get('hook_schedule') and mode.get('detach_water_at') is None)
    if not eligible or mode.get('renderdoc') or mode.get('capture_at') is not None:
        errors.append('NOT_CONTINUOUS_NO_CAPTURE_MODE')
    if controlled:
        if identity(args.run / 'control_request.json')['sha256'] != decision['formal_control_request']['sha256']:
            errors.append('FROZEN_CONTROL_REQUEST_MISMATCH')
        if not mode.get('control_request') or mode['control_request']['sha256'] != decision['formal_control_request']['sha256']:
            errors.append('CONTROL_HOST_REQUEST_MISMATCH')
    for key in ['native_scalars', 'clock_sample_every', 'shadow_every']:
        if mode.get(key) != rec[key]:
            errors.append('CONFIG_MISMATCH:' + key)
    source_errors = []
    for expected in decision['sources']:
        saved = args.run / 'sources' / expected.get('saved_name', Path(expected['path']).name)
        if Path(expected['path']).name == 'freeze_d07.py':
            continue
        if not saved.exists() or identity(saved)['sha256'] != expected['sha256']:
            source_errors.append(str(saved))
    if source_errors:
        errors.append('FROZEN_OBSERVER_SOURCE_MISMATCH')
    if not stats.get('native_scalar') or stats['native_scalar']['overflow']:
        errors.append('NATIVE_SCALAR_CACHE_NOT_CLOSED')
    present = [e for row in raw if row.get('payload', {}).get('kind') == 'presentation_trace' for e in row['payload']['events']]
    if [e['seq'] for e in present] != list(range(1, ps['last_seq'] + 1)) or any(ps[k] for k in ['errors', 'dropped', 'inflight']):
        errors.append('PRESENT_LOG_NOT_CLOSED')
    entries = [e for e in present if e['kind'] == 'present_enter']
    returns = [e for e in present if e['kind'] == 'present_return']
    if collections.Counter(e['call_id'] for e in entries) != collections.Counter(e['call_id'] for e in returns) or len(entries) != ps['presents'] or len(returns) != ps['returns']:
        errors.append('PRESENT_CALLS_NOT_PAIRED')
    if any(e['hresult'] != 0 for e in returns):
        errors.append('PRESENT_FAILED')
    freq = int(next(e['qpc_frequency'] for e in present if e['kind'] == 'loaded'))
    epoch = int(next(e['marker_qpc'] for e in present if e['kind'] == 'host_marker' and e['label'] == 'before_resume'))
    low, high = [epoch + int(t * freq) for t in rec['formal_window_from_before_resume_qpc_seconds']]
    states = [e for e in present if e['kind'] == 'window_state']
    selected_states = [e for e in states if low <= int(e['qpc']) <= high]
    before, after = [e for e in states if int(e['qpc']) < low], [e for e in states if int(e['qpc']) > high]
    coverage = before[-1:] + selected_states + after[:1]
    gap = max(((int(b['qpc']) - int(a['qpc'])) / freq for a, b in zip(coverage, coverage[1:])), default=float('inf'))
    if not before or not after or len(selected_states) < 2 * cfg['minimum_window_state_samples_per_window'] or gap > cfg['maximum_window_state_gap_seconds']:
        errors.append('WINDOW_STATE_COVERAGE_INSUFFICIENT')
    if any(not e['visible'] or e['minimized'] or not e['foreground_owned'] or (e['client_width'], e['client_height']) != (cfg['actual_render_width'], cfg['actual_render_height']) or any(e.get('input', {}).get(k) for k in ['left', 'right', 'middle']) for e in coverage):
        errors.append('WINDOW_OR_SAMPLED_INPUT_NOT_MATCHED')
    descriptions = [e for e in present if e['kind'] in ['swapchain', 'swapchain_resize'] and e.get('description_result') == 0 and int(e['qpc']) <= low]
    if not descriptions or (descriptions[-1]['width'], descriptions[-1]['height']) != (cfg['actual_render_width'], cfg['actual_render_height']):
        errors.append('ACTUAL_SWAPCHAIN_SIZE_MISMATCH')
    window_present = [e for e in entries if low <= int(e['qpc']) <= high]
    if any(e['sync_interval'] != cfg['expected_present_sync_interval'] or e['flags'] != cfg['expected_present_flags'] for e in window_present):
        errors.append('PRESENT_OPTIONS_MISMATCH')
    intervals = [(int(b['qpc']) - int(a['qpc'])) / freq * 1000 for a, b in zip(entries, entries[1:]) if low <= int(a['qpc']) <= int(b['qpc']) <= high]
    calls = [e for e in water if e['kind'] == 'dispatch_enter']
    sources = [e for e in calls if e['kernel_name'] == 'UpdateAmount']
    clocks = [e for e in water if e['kind'] == 'engine_clock_sample']
    if collections.Counter(e['call_id'] for e in sources) != collections.Counter(e['call_id'] for e in clocks):
        errors.append('PER_SOURCE_CLOCK_NOT_CLOSED')
    window_sources = [e for e in sources if low <= int(e['qpc']) <= high]
    if not window_sources or not intervals:
        errors.append('NO_FORMAL_WINDOW_SAMPLES')
    parameters = {name: sorted({property_value(d, name, 'global_parameters' if name == 'playTime' else 'parameters') for d in window_sources}, key=str) for name in ['deltaTime', 'waveAmplitude', 'customWave', 'level', 'evaporationFactor', 'playTime']}
    if len(parameters['waveAmplitude']) < 2 or len(parameters['playTime']) < 2:
        errors.append('NATURAL_PARAMETER_PROGRESSION_NOT_OBSERVED')
    fingerprint = []
    for item in manifest['artifacts']:
        actual = identity(item['path'])
        if actual['sha256'] != item['sha256'] or actual['size_bytes'] != item['size_bytes']:
            fingerprint.append(item['path'])
    if fingerprint or manifest['operation_status'] != 'complete' or not manifest['watched_source_and_user_data_unchanged'] or manifest['elapsed_seconds'] < rec['formal_no_capture_run_seconds']:
        errors.append('RUN_OR_SOURCE_NOT_CLOSED')
    result = dict(operation_status='complete', verification_status='passed' if not errors else 'failed',
                  scope=('Held public engine Time intervention; requires separate control/phase audit. Not original UI behavior or G4.' if controlled else 'No active input / natural parameter progression only. Does not prove physical still water, input absence between samples, controllable-input coverage or G4.'),
                  decision=identity(args.decision), runtime=identity(args.run / 'manifest.json'),
                  qpc_frequency=freq, epoch_qpc=str(epoch), window_qpc=[str(low), str(high)],
                  state_samples=len(selected_states), max_state_gap_seconds=gap,
                  present_intervals_ms=metrics(intervals), window_source_count=len(window_sources),
                  source_count=len(sources), native_clock_count=len(clocks), parameter_values=parameters,
                  source_mismatches=source_errors, artifact_identity_errors=fingerprint, errors=errors)
    (out / 'trajectory.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    (out / 'manifest.json').write_text(json.dumps(dict(operation_status='complete', verification_status=result['verification_status'], errors=errors, artifacts=[identity(p) for p in out.iterdir() if p.is_file()]), indent=2), encoding='utf-8')
    print(json.dumps({k:result[k] for k in ['verification_status', 'state_samples', 'window_source_count', 'source_count', 'native_clock_count', 'errors']}))
    raise SystemExit(bool(errors))


if __name__ == '__main__':
    main()
