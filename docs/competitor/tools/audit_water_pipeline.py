"""Audit existing test1 raw evidence and snapshot the current project comparison.

Read-only inputs; no replay, simulation, original HLSL or wall-clock claim.
Usage: python -X utf8 docs/competitor/tools/audit_water_pipeline.py --output <new ASCII absolute directory>
"""
import argparse
import collections
import hashlib
import json
import math
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
EXPECTED = '761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2'
EVIDENCE = ROOT / 'docs/competitor/evidence'
AUDIT = EVIDENCE / 'shader_execution_20261025'
MANIFESTS = [
    'water_schedule_20261024_v2/manifest.json',
    'shader_execution_20261025/selected_v1/manifest.json',
    'shader_execution_20261025/graphics_v1/manifest.json',
    'shader_execution_20261025/post_v1/manifest.json',
    'shader_execution_20261025/views_v2/manifest.json',
    'shader_execution_20261025/timing_v1/manifest.json',
    'foam_comparison_20261024/rdc/manifest.json',
    'wet_sand_20261024/rdc/manifest.json',
    'wet_sand_20261024/package/manifest.json',
    'material_quality_20261023/rdc/manifest.json',
]
PROJECT = [
    'project.godot', 'scenes/main.tscn', 'scenes/playable/test1_geometry.tscn',
    'scenes/unified_edit/presentation/main.tscn',
    'scenes/unified_edit/presentation/test1_geometry.tscn',
    'assets/unified_edit/presentation/main.json',
    'assets/unified_edit/presentation/test1_geometry.json',
    'assets/parameters/catalog.json',
    'assets/test1_geometry/water_cycle.json',
    'scripts/scenarios/test1_geometry_layout.gd',
    'assets/water_material_natural_candidate/async_rdc_water.gdshader',
    'assets/water_material_natural_candidate/async_rdc_bed.gdshader',
    'assets/water_material_natural_candidate/contact_shape.gdshader',
    'assets/water_material_natural_candidate/rdc_caustic_manifest.json',
    'assets/water_sides/water_sides.gdshader',
    'scripts/beach/unified_playable_entry.gd',
    'scripts/simulation/unified_edit/water.gd',
    'scripts/simulation/unified_edit/water_muscl.gd',
    'scripts/simulation/unified_edit/water_numerics.gd',
    'scripts/simulation/unified_edit/coupled.gd',
    'scripts/simulation/unified_edit/visuals.gd',
    'scripts/simulation/unified_edit/state.gd',
    'scripts/simulation/unified_edit/pipeline.gd',
    'scripts/simulation/unified_edit/presentation.gd',
    'scripts/simulation/unified_edit/boundary.gd',
    'scripts/simulation/unified_edit/boundary.glsl',
    'scripts/simulation/unified_edit/publish_wet_sand.glsl',
    'scripts/simulation/unified_edit/surface_wetness.gd',
    'scripts/simulation/unified_edit/shore_splash.gd',
    'shaders/simulation/shore_splash.glsl',
    'shaders/simulation/visual_foam_step.glsl',
    'shaders/simulation/muscl/muscl_math.glslinc',
    'shaders/simulation/muscl/muscl_spatial.glslinc',
    'shaders/simulation/muscl/rk_decide.glsl',
    'shaders/simulation/muscl/rk_finalize.glsl',
    'shaders/simulation/muscl/rk_edge.glsl',
    'shaders/simulation/muscl/rk_drain.glsl',
    'shaders/simulation/muscl/rk_euler.glsl',
    'shaders/simulation/erosion/sediment_exchange.glsl',
]


def identity(path):
    data = path.read_bytes()
    return {'path': path.as_posix(), 'bytes': len(data),
            'sha256': hashlib.sha256(data).hexdigest()}


def records(obj):
    if isinstance(obj, dict):
        if isinstance(obj.get('path'), str) and 'sha256' in obj:
            yield obj
        for value in obj.values():
            yield from records(value)
    elif isinstance(obj, list):
        for value in obj:
            yield from records(value)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    out = parser.parse_args().output
    if not out.is_absolute() or not str(out).isascii():
        raise ValueError('Output must be an absolute ASCII path')
    out.mkdir(parents=True, exist_ok=False)
    report = {'scope': 'Existing raw-byte/constant/instruction audit; current repository defaults, not runtime user overrides. No new replay or timing.',
              'script': identity(Path(__file__).resolve()),
              'command': sys.argv, 'python': sys.version,
              'sources': [], 'manifests': [], 'checked_records': [],
              'missing_or_changed': [], 'project_snapshots': [], 'derived': {}}
    cache = {}
    def checked(path):
        key = str(path)
        if key not in cache:
            cache[key] = identity(path) if path.is_file() else None
        return cache[key]

    for name in ['sandcastlegame/test1.rdc', 'rdc/test1.rdc',
                 'sandcastlegame/Sandcastle_Data/sharedassets0.assets']:
        item = checked(ROOT / name)
        report['sources'].append(item)
        if item is None or (name.endswith('.rdc') and item['sha256'] != EXPECTED):
            raise ValueError('Source identity unavailable or wrong: ' + name)

    seen = set()
    for relative in MANIFESTS:
        path = EVIDENCE / relative
        data = json.loads(path.read_text(encoding='utf-8-sig'))
        report['manifests'].append(identity(path))
        for rec in records(data):
            p = Path(rec['path'])
            if not p.is_absolute():
                p = path.parent / p
            pair = (p.as_posix(), rec['sha256'])
            if pair in seen:
                continue
            seen.add(pair)
            actual = checked(p)
            entry = {'manifest': path.as_posix(), 'expected': rec, 'actual': actual,
                     'match': actual is not None and actual['sha256'] == rec['sha256']
                     and ('bytes' not in rec or actual['bytes'] == rec['bytes'])}
            report['checked_records'].append(entry)
            if not entry['match']:
                report['missing_or_changed'].append(entry)

    for relative in PROJECT:
        source = ROOT / relative
        destination = out / 'project_snapshot' / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        payload = source.read_bytes()
        destination.write_bytes(payload)
        report['project_snapshots'].append({'source': identity(source), 'snapshot': identity(destination)})

    selected = AUDIT / 'selected_v1'
    def cb(event, stage, register, fmt='4f', slot=0):
        raw = (selected / f'e{event}_{stage}_cb{slot}.bin').read_bytes()
        return list(struct.unpack_from('<' + fmt, raw, register * 16))
    report['derived']['constants'] = {
        'water_grid_uint': cb(1495, 'cs', 155, '4I')[:2],
        'water_dx_inverse_dx': cb(1495, 'cs', 154),
        'water_dt_gravity': cb(1495, 'cs', 157)[2:],
        'foam_capacity_uint': cb(1550, 'cs', 138, '4I')[0],
        'foam_dt': cb(1550, 'cs', 152)[2],
        'foam_water_grid_uint': cb(1550, 'cs', 152, '4I')[:2],
        'source_dt': cb(1537, 'cs', 157)[2],
        'source_evaporation_wave_amplitude': [cb(1537, 'cs', 158)[i] for i in [1,3]],
        'source_custom_wave_level': [cb(1537, 'cs', 159)[i] for i in [0,2]],
        'velocity_max_damping_kappa': [cb(1490, 'cs', 158)[0], cb(1490, 'cs', 159)[1], cb(1490, 'cs', 159)[3]],
        'advection_factor': cb(1500, 'cs', 158)[2],
        'water_rgb_tint': cb(6083, 'ps', 131)[:3],
        'water_absorption_input': cb(6083, 'ps', 132)[:3],
        'water_surface_color': cb(6083, 'ps', 121)[:3],
        'water_refraction': cb(6083, 'ps', 0, slot=1)[0],
    }
    # Exact bit constants are visible in hex disassembly, unlike generic asm.
    hpath = AUDIT / 'analysis_v1/e1495_cs.hex.asm'
    h = hpath.read_text()
    required = ['0x00000EC0: lt r0.yz, l(0x00000000, 0x3dcccccd, 0x3f000000',
                '0x00000F04: and r0.y, r0.y, l(0x00ff0000)']
    report['derived']['foam_instruction_checks'] = {
        'hex_source': identity(hpath), 'required_fragments': required,
        'all_present': all(x in h for x in required),
        'rise_threshold_float32': struct.unpack('<f', struct.pack('<I', 0x3dcccccd))[0],
        'normal_xz_threshold': 0.5,
        'field': 'uint4.w bits16..23',
        'producer': 'E1495/E1510/E1525 HeightIntegration, instructions97/100/106/112-123',
        'consumer': 'E1550 instructions62-64/78-79/91-93/108-109/116-132/144-147',
        'state_equation': 's_next=saturate(s_reset + dt*(2*bilinear(B)-0.2)); low s<0.01 resets s to0.01 and random xz',
        'position_equation': 'xz_next=clamp(xz_reset +0.5*dt*bilinear(v)*[bilinear(A)>0.05],domain); y=floor+max(A-0.05,0) at queried position',
        'cull_s_threshold_approx': -math.log(0.8) / 4.0,
        'boundary': 'Static compiled dataflow. Does not measure real seconds, continuous lifecycle, pre/post equivalence or visual causality.'}
    # Every iteration of the propagation chain uses the same HeightIntegration program.
    manifest = json.loads((selected / 'manifest.json').read_text())
    rows = {e['event']: e for e in manifest['events']}
    report['derived']['height_shader_hashes'] = {
        str(e): rows[e]['stages']['cs']['bytecode']['sha256'] for e in [1495,1510,1525]}
    report['derived']['dataflow_bindings'] = {
        str(e): {s: r['bindings'] for s, r in rows[e]['stages'].items()}
        for e in [1495,1510,1525,1530,1537,1543,1550,1634,6083,6196]}

    rawpath = EVIDENCE / 'foam_comparison_20261024/rdc/e1550_cs_read_139573.bin'
    raw = rawpath.read_bytes()
    flags = collections.Counter((words[3] >> 16) & 255 for words in struct.iter_unpack('<4I', raw))
    report['derived']['water_flag_snapshot'] = {
        'raw': identity(rawpath), 'selector': 'Existing E1550 t0 R139573 complete buffer',
        'cells': len(raw)//16, 'flag_value_counts': dict(flags),
        'limitation': 'Snapshot classification, not replayed output-vs-input verification or screen coverage.'}
    a = (EVIDENCE / 'foam_comparison_20261024/rdc/e6196_vs_read_139582.bin').read_bytes()
    indices = (EVIDENCE / 'foam_comparison_20261024/rdc/e6196_vs_read_139575.bin').read_bytes()
    active = []
    for i in struct.unpack_from('<29950I', indices):
        active.append(struct.unpack_from('<f', a, i*16)[0])
    report['derived']['selected_foam_strength'] = {
        'samples': len(active), 'minimum': min(active), 'maximum': max(active),
        'all_above_cull_threshold': min(active) >= -math.log(0.8)/4 - 1e-6,
        'below_threshold': sum(s < -math.log(0.8)/4 for s in active),
        'unique_indices': len(set(struct.unpack_from('<29950I', indices))),
        'limitation': 'E6196 saved action count vs replayed index/state; not a consistent cull snapshot. Root cause unknown; do not infer lifetime or particle counts from it.'}
    foam_dir = EVIDENCE / 'foam_comparison_20261024/rdc'
    cull_state = (foam_dir/'e1634_cs_write_139582.bin').read_bytes()
    cull_indices = (foam_dir/'e1634_cs_write_139575.bin').read_bytes()
    args = struct.unpack('<5I', (foam_dir/'e1634_cs_write_139579.bin').read_bytes())
    ids = struct.unpack_from('<%dI' % args[1], cull_indices)
    strengths = [struct.unpack_from('<f', cull_state, i*16)[0] for i in ids]
    report['derived']['cull_snapshot'] = {
        'selector': 'E1634 R139579 arguments, R139575 indices, R139582 states, matching event exports',
        'arguments': list(args), 'unique_indices': len(set(ids)),
        'minimum_s': min(strengths),
        'below_threshold': sum(s < -math.log(0.8)/4 for s in strengths),
        'limitation': 'Replayed cull count 31115 is not recorded E6196 action count29950. No cross-event conservation or determinism claim.'}
    historical = [
        'test_output/test1_water_motion/capture_v1/manifest.json',
        'test_output/test1_water_motion/analysis_v1/stage_validation.json',
        'test_output/competitor_water_material_20261011/pixel_v2/manifest.json',
        'test_output/water_material_rdc/caustic_mips_v1/manifest.json']
    report['historical_availability'] = [{
        'path': (ROOT/p).as_posix(), 'exists': (ROOT/p).is_file()} for p in historical]
    report['revision_note'] = 'audit_v2 narrows constant names to consumed registers and records the E1634 positive/E6196 conflicting index-state checks; audit_v1 is preserved.'
    report['sources_after'] = [identity(Path(s['path'])) for s in report['sources']]
    report['source_unchanged'] = report['sources'] == report['sources_after']
    report['project_sources_unchanged'] = all(identity(Path(s['source']['path'])) == s['source']
                                              for s in report['project_snapshots'])
    report['mechanical_pass'] = (not report['missing_or_changed'] and report['source_unchanged']
                                 and report['project_sources_unchanged']
                                 and report['derived']['foam_instruction_checks']['all_present'])
    (out/'audit.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({k: report[k] for k in ['scope','mechanical_pass','source_unchanged','project_sources_unchanged','historical_availability']},ensure_ascii=False,indent=2))
    print('Checked records:', len(report['checked_records']), 'issues:', len(report['missing_or_changed']))
    print(json.dumps(report['derived'],ensure_ascii=False,indent=2)[:4500])
    if report['missing_or_changed']:
        print(json.dumps(report['missing_or_changed'],ensure_ascii=False,indent=2))


if __name__ == '__main__':
    main()
