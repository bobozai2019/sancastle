"""Independent inlet formula, ordered GPU stages and native wave-state audit."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct

import numpy as np
from native_variant import VariantReader

ROOT = Path(__file__).resolve().parents[2]
CASES = ['boundary_main', 'boundary_capture', 'boundary_backwash', 'boundary_geometry', 'boundary_geometry_rise', 'boundary_geometry_fall', 'boundary_queued', 'boundary_capacity', 'boundary_upload']


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cases', nargs='+', choices=CASES, help='Explicit subset; omission requires the nine-case matrix')
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit('Fresh audit required')
    checks = []
    math_diagnostics = []

    def check(name, ok):
        checks.append({'name': name, 'pass': bool(ok)})

    def sha(data):
        return hashlib.sha256(data).hexdigest()

    def raw(meta, label):
        data = Path(meta['path']).read_bytes()
        check(label+'_sha', sha(data) == meta['sha256'].lower())
        if 'bytes' in meta:
            check(label+'_bytes', len(data) == meta['bytes'])
        return data

    def smooth(a, b, x):
        t = max(0.0, min(1.0, (x-a)/(b-a)))
        return t*t*(3-2*t)

    def budget(a, b):
        return np.maximum(2e-7, 16*np.abs(np.spacing(np.maximum(np.abs(a), np.abs(b)).astype('<f4')))+16*2**-24*np.abs(b-a))

    def stage(label, meta):
        data = {key: raw(value, label+'_'+key) for key, value in meta.items() if isinstance(value, dict)}
        area, mean, amplitude, omega, count, mode, phase, period = struct.unpack('<4f2I2f', data['push'])
        check(label+'_effective_packet_count', count == meta['packet_count'])
        packets = np.frombuffer(data['packet_bytes'], dtype='<f4').reshape(128, 4)
        trace = np.frombuffer(data['math_trace'], dtype='<f4').reshape(129, 4)
        check(label+'_unused_packet_bytes_zero', np.all(packets[count:] == 0))
        time = struct.unpack_from('<f', data['before/control'], 32)[0]
        wave = 0.0;observed_sum = np.float32(0);maximum_sine_error = 0.0
        for index, (start, duration, height, seed) in enumerate(packets[:count]):
            u = (time-float(start))/float(duration)
            if 0 <= u < 1:
                wave += float(height)*math.sin(math.pi*u)**2*(.95+.05*math.sin(2*math.pi*u+float(seed)))
                gpu_u, envelope, oscillation, term = (float(v) for v in trace[index])
                check(label+'_gpu_u_'+str(index), abs(gpu_u-u) <= budget(0, u))
                sine_error = max(abs(envelope-math.sin(math.pi*u)), abs(oscillation-math.sin(2*math.pi*u+float(seed))))
                maximum_sine_error = max(maximum_sine_error, sine_error)
                # DXIL Sin specifies absolute error <= .0008 for [-100pi,100pi],
                # not the physical edit cell budget or host-libm rounding:
                # https://github.com/microsoft/DirectXShaderCompiler/blob/main/docs/DXIL.rst#sin
                check(label+'_gpu_primitive_domain_'+str(index), 0 <= math.pi*u <= 100*math.pi and abs(2*math.pi*u+float(seed)) <= 100*math.pi)
                check(label+'_gpu_sine_primitive_'+str(index), math.isfinite(sine_error) and sine_error <= .0008)
                expected_term = float(height)*envelope*envelope*(.95+.05*oscillation)
                check(label+'_gpu_term_'+str(index), abs(term-expected_term) <= 16*abs(np.spacing(np.float32(expected_term))))
                observed_sum = np.float32(observed_sum+np.float32(term))
            else:
                check(label+'_inactive_term_'+str(index), np.all(trace[index, 1:] == 0))
        ideal_wave = min(wave, .25)
        check(label+'_trace_identity', trace[128, 0] == time and trace[128, 2] == count and trace[128, 3] == 1)
        check(label+'_independent_device_sum', abs(trace[128, 1]-min(float(observed_sum), .25)) <= budget(0, float(observed_sum)))
        wave = float(trace[128, 1])
        base = mean*(.5+.5*math.cos(2*math.pi*time/period)) if mode == 2 else mean
        level = base+amplitude*math.sin(phase+time*omega)+wave
        if mode == 3:
            t = math.fmod(time, period)/period
            level = mean+amplitude*smooth(.05, .20, t)*(1-smooth(.25, .45, t))+wave
        rock = np.frombuffer(data['before/rock'], dtype='<f4').reshape(256, 256)
        sand = np.frombuffer(data['before/sand'], dtype='<f4').reshape(256, 256)
        check(label+'_boundary_does_not_change_bed', data['before/rock'] == data['after/rock'] and data['before/sand'] == data['after/sand'])
        rows = np.arange(68, 188) if mode == 3 else np.arange(256)
        mask = np.zeros((256, 256), dtype=bool);mask[rows, 0] = True
        bed = rock[rows, 0]+sand[rows, 0]
        depth = np.maximum(0, level-bed.astype(float))
        background = np.maximum(0, level-wave-bed.astype(float))
        expected = {'water': depth, 'momentum_x': np.where(depth > 0, wave*np.sqrt(9.81*np.maximum(background, .01)), 0), 'momentum_z': np.zeros(len(rows))}
        for field, target in expected.items():
            before = np.frombuffer(data['before/'+field], dtype='<f4').reshape(256, 256)
            after = np.frombuffer(data['after/'+field], dtype='<f4').reshape(256, 256)
            check(label+'_only_inlet_changes_'+field, np.array_equal(before.view('<u4')[~mask], after.view('<u4')[~mask]))
            check(label+'_independent_formula_'+field, np.all(np.abs(after[rows, 0].astype(float)-target) <= budget(before[rows, 0].astype(float), target)))
        actual_level, actual_wave = struct.unpack_from('<2f', data['after/control'], 96)
        check(label+'_level_wave_diagnostics', abs(actual_level-level) <= budget(mean, level) and abs(actual_wave-wave) <= budget(0, wave))
        math_diagnostics.append({'label': label, 'packet_count': count, 'time_s': time, 'host_libm_wave': ideal_wave, 'actual_boundary_wave': actual_wave, 'actual_trace_wave': wave, 'maximum_observed_sine_error': maximum_sine_error, 'physical_and_total_wave_budget_changed': False})
        before_water = np.frombuffer(data['before/water'], dtype='<f4').reshape(256, 256)
        after_water = np.frombuffer(data['after/water'], dtype='<f4').reshape(256, 256)
        delta = ((after_water[rows, 0]-before_water[rows, 0])*np.float32(area)).astype('<f4')
        for field, offset, amounts in [('source', 88, np.maximum(delta, 0)), ('sink', 92, np.maximum(-delta, 0))]:
            lanes = np.zeros(64, dtype='<f4')
            for z, value in zip(rows, amounts):
                lanes[z % 64] = np.float32(lanes[z % 64]+value)
            for stride in (32, 16, 8, 4, 2, 1):
                lanes[:stride] = lanes[:stride]+lanes[stride:2*stride]
            old = struct.unpack_from('<f', data['before/control'], offset)[0]
            actual = struct.unpack_from('<f', data['after/control'], offset)[0]
            target = np.float32(np.float32(old)+lanes[0])
            check(label+'_actual_inlet_ledger_'+field, actual == target)
        return count, mode, time, level, wave

    manifest = json.loads((args.run/'run-manifest.json').read_text(encoding='utf-8-sig'))
    check('manifest_pass', manifest['pass'] and not manifest['drift'])
    check('exact_cases', [r['case'] for r in manifest['runs']] == (args.cases or CASES))
    for path, expected in manifest['sources'].items():
        check('source_'+path, sha((ROOT/path).read_bytes()) == expected.lower())
    for run in manifest['runs']:
        case = run['case'];payload = Path(run['result']).read_bytes()
        check(case+'_report_sha', sha(payload) == run['result_sha256'].lower())
        report = json.loads(payload);obs = report['observations']
        check(case+'_gpu_pass', run['pass'] and report['pass'] and all(c['pass'] for c in report['checks']))
        for name in ['stdout.txt', 'probe.log']:
            text = (Path(run['result']).parent/name).read_text(encoding='utf-8-sig')
            check(case+'_clean_'+name, 'SCRIPT ERROR:' not in text and '\nERROR:' not in text and 'were leaked' not in text and 'was leaked' not in text)
        snapshots = {}
        for name in ['initial', 'first', 'after_save', 'restored', 'source_second', 'candidate_second', 'after_upload_failure']:
            if name in obs:
                snapshots[name] = {key: raw(meta, case+'_'+name+'_'+key) for key, meta in obs[name].items()}
        if case == 'boundary_upload':
            check(case+'_known_unrecorded_no_authority_change', snapshots['initial'] == snapshots['after_upload_failure'])
            check(case+'_no_container', not (Path(run['result']).parent/'boundary.sandue').exists())
            check(case+'_all_owners_zero', len(obs['source_ownership']) == 8 and all(n == 0 for n in obs['source_ownership'].values()))
            continue
        for name in ['source_ownership', 'final_ownership']:
            check(case+'_all_eight_owners_zero_'+name, len(obs[name]) == 8 and all(n == 0 for n in obs[name].values()))
        stages = [stage(case+'_first_'+str(i), meta) for i, meta in enumerate(obs['stages'])]
        if case in ('boundary_geometry_rise', 'boundary_geometry_fall'):
            fixture = raw(obs['clock_fixture'], case+'_clock_fixture')
            header = VariantReader(fixture[48:]).document()
            expected_time = 3.0 if case == 'boundary_geometry_rise' else 7.0
            check(case+'_explicit_synthetic_clock_fixture', header['advanced_time_s'] == expected_time and struct.unpack_from('<f', header['native']['control'], 32)[0] == expected_time and stages[0][2] == expected_time and header['source_provenance']['trusted_fixture']['role'] == 'synthetic_clock_only')
            check(case+'_actual_nonrest_phase', stages[0][3] > .95+stages[0][4]+.1)
            check(case+'_fixture_previous_owners_zero', all(n == 0 for n in obs['clock_fixture']['original_owners_after_release'].values()))
        check(case+'_pending_freezes_wave_snapshot', [s[0] for s in stages] == ([0, 2] if case == 'boundary_queued' else [128 if case == 'boundary_capacity' else 2]))
        for name in ['source_stages', 'candidate_stages']:
            for i, meta in enumerate(obs[name]):
                stage(case+'_'+name+'_'+str(i), meta)
        container = raw(obs['container'], case+'_container')
        check(case+'_container_header', container[:8] == b'SANDUE06' and struct.unpack_from('<II', container, 8) == (1, len(container)-48) and sha(container[48:]) == container[16:48].hex())
        cp = VariantReader(container[48:]).document()
        check(case+'_prescribed_boundary', cp['simulation']['prescribed_tide_boundary'] and cp['configuration']['environment']['boundary']['enabled'])
        count = 128 if case == 'boundary_capacity' else 2
        check(case+'_wave_identity_highwater', cp['wave_highwater_id'] == count and len(cp['wave_requests']) == count)
        expected = bytearray(2048)
        for i, wave in enumerate(cp['wave_requests']):
            start = cp['wave_start_times'][wave['request_id']]
            struct.pack_into('<4f', expected, i*16, start, wave['duration_s'], wave['amplitude_m'], (wave['seed'] & 1023)*2*math.pi/1024)
            check(case+'_wave_generation_'+str(i), wave['generation'] == cp['generation'])
        check(case+'_actual_saved_gpu_binding', bytes(expected) == snapshots['after_save']['boundary_waves'] == snapshots['restored']['boundary_waves'])
        check(case+'_all_registered_capture_readers', len(obs['capture_info']['records']) == 37)
        check(case+'_all_registered_restore_readers', len(obs['verifier']) == 46 and all(v['matched'] for v in obs['verifier'].values()))
        for key, value in cp['native']['fields'].items():
            check(case+'_native_field_'+key, value == snapshots['after_save']['field/'+key] == snapshots['restored']['field/'+key])
        for key, value in cp['native']['spare'].items():
            check(case+'_native_spare_'+key, value == snapshots['after_save']['spare/'+key] == snapshots['restored']['spare/'+key])
        for key in snapshots['source_second']:
            if key not in ('control', 'stamp'):
                check(case+'_continued_exact_'+key, snapshots['source_second'][key] == snapshots['candidate_second'][key])
        maps = np.frombuffer(raw(obs['physics']['maps'], case+'_maps'), dtype='<f4').reshape(64, 33, 33)
        bed = np.frombuffer(cp['native']['fields']['rock'], dtype='<f4').reshape(256, 256)+np.frombuffer(cp['native']['fields']['sand'], dtype='<f4').reshape(256, 256)
        for chunk in range(64):
            xs = np.minimum(255, (chunk % 8)*32+np.arange(33));zs = np.minimum(255, (chunk // 8)*32+np.arange(33))
            check(case+'_physics_'+str(chunk), np.array_equal(maps[chunk], bed[np.ix_(zs, xs)]))
        headers = VariantReader(raw(obs['second_headers']['headers'], case+'_second_headers')).document()
        check(case+'_second_capture_continued_ledger', len(headers) == 2 and headers[0]['ledger'] == headers[1]['ledger'] and headers[0]['times'] == headers[1]['times'] and headers[0]['tick'] == headers[1]['tick'] == cp['sim_tick']+1)
    result = {'pass': all(c['pass'] for c in checks), 'checks': checks, 'math_diagnostics': math_diagnostics, 'intrinsic_reference': 'https://github.com/microsoft/DirectXShaderCompiler/blob/main/docs/DXIL.rst#sin', 'intrinsic_absolute_error_bound': .0008, 'physical_and_total_wave_budget_changed': False, 'tool_sha256': sha(Path(__file__).read_bytes()), 'scope': 'Only listed boundary cases: original inlet formula via ordered before/after readbacks, device sine intermediates and independently reconstructed sums, exact inlet ledger reduction, pending frozen packets, wave buffer/native container, combined erosion+visual histories, 64 maps and continuation. No formal entry, full lifecycle or performance claim.'}
    args.output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps({'pass': result['pass'], 'checks': len(checks), 'failures': [c['name'] for c in checks if not c['pass']]}))
    return 0 if result['pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
