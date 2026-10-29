"""Read-only inventory for an isolated competitor-equation water test scene."""
import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FILES = [
    'shaders/simulation/test1_water_motion.glsl',
    'scripts/visual/test1_water_motion_trial.gd',
    'scripts/visual/test1_main_presentation.gd',
    'shaders/simulation/test1_main_display.glsl',
    'assets/test1_water_motion/capture_profile.json',
    'assets/test1_water_motion/capture_state.rgba32f',
    'assets/test1_water_motion/capture_aux.rgba32f',
    'assets/test1_water_motion/main_presentation.json',
    'tests/investigation/test1_water_motion/model.py',
    'tests/investigation/test1_water_motion/build_fixture_inputs.py',
    'scripts/simulation/unified_edit/state.gd',
]
MISSING_CANDIDATES = [
    'scenes/test1_water_motion_trial.tscn',
    'test_output/test1_water_motion/capture_v1/manifest.json',
    'test_output/test1_water_motion/analysis_v1/stage_validation.json',
    'test_output/test1_water_motion/main_material_review_v1/summary.json',
]


def identity(path):
    result = {'path': path.as_posix(), 'exists': path.is_file()}
    if result['exists']:
        data = path.read_bytes()
        result.update(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    out = parser.parse_args().output
    if not out.is_absolute() or not str(out).isascii():
        raise ValueError('Use a new absolute ASCII output directory')
    out.mkdir(parents=True, exist_ok=False)
    result = {'scope': 'Static availability and identity only; no Godot launch, new replay, kernel equivalence or performance claim.',
              'script': identity(Path(__file__)), 'command': sys.argv,
              'source': identity(ROOT / 'sandcastlegame/test1.rdc'),
              'files': [], 'historical_availability': [], 'asset_checks': []}
    for relative in FILES:
        p = ROOT / relative
        record = {'source': identity(p)}
        if p.is_file():
            target = out / 'sources' / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(p, target)
            record['snapshot'] = identity(target)
        result['files'].append(record)
    for relative in MISSING_CANDIDATES:
        result['historical_availability'].append(identity(ROOT / relative))
    profile = json.loads((ROOT / 'assets/test1_water_motion/capture_profile.json').read_text(encoding='utf-8'))
    for expected in profile['artifacts']:
        actual = identity(Path(expected['path']))
        result['asset_checks'].append({'expected': expected, 'actual': actual,
                                      'match': all(expected[k] == actual.get(k) for k in ['bytes', 'sha256'])})
    result['capture_matches_profile'] = result['source'].get('sha256') == profile['source_sha256']
    result['state_selector'] = profile['state_selector']
    result['source_after'] = identity(ROOT / 'sandcastlegame/test1.rdc')
    result['source_unchanged'] = result['source'] == result['source_after']
    result['inspected_files_unchanged'] = all(identity(Path(r['source']['path'])) == r['source'] for r in result['files'])
    result['limits'] = [
        'Preserved float seed is a derivative selected at E6083, not E1490 pre-dispatch input.',
        'Matching derivative hashes do not recover missing original stage snapshots.',
        'Historical runtime success is not revalidated by this inventory.',
    ]
    (out / 'inventory.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'capture_matches_profile': result['capture_matches_profile'],
                      'asset_matches': [r['match'] for r in result['asset_checks']],
                      'historical_availability': result['historical_availability'],
                      'source_unchanged': result['source_unchanged'],
                      'inspected_files_unchanged': result['inspected_files_unchanged']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
