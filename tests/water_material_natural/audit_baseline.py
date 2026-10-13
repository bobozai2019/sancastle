"""Audit source identity, capture artifacts, and repeated completed-state bytes."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]

def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def identity(path):
    return {'path': str(path.resolve()), 'bytes': path.stat().st_size, 'sha256': sha(path)}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('first', type=Path)
    parser.add_argument('second', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = {'pass': False, 'sources': [], 'checks': {}, 'unknowns': [
        'Competitor original normal UV/time formula and complete reflection model unknown.',
        'Package-to-runtime texture equivalence not revalidated; use confirmed runtime texels.',
        'No visual acceptance implied by successful capture.']}
    try:
        old = ROOT/'docs/history/sandcastle_test1_reverse_rebuild/data/index/source_files.jsonl'
        rows = [json.loads(line) for line in old.read_text(encoding='utf-8').splitlines()]
        for row in rows:
            if row['source_relpath'] in ('test1.rdc', 'Sandcastle_Data/sharedassets0.assets',
                                        'Sandcastle_Data/sharedassets0.assets.resS'):
                path = Path(row['absolute_path'])
                record = identity(path)
                record['matches_historical'] = record['sha256'] == row['sha256']
                result['sources'].append(record)
                assert record['matches_historical'], 'source changed: ' + str(path)
        first, second = [json.loads((p/'manifest.json').read_text()) for p in (args.first,args.second)]
        for capture in (first, second):
            assert capture['driver'] == 'd3d12'
            assert capture['tick'] == 360 and capture['visual_time_s'] == 12.0
            assert set(capture['cameras']) == {'oblique','close','grazing'}
            for field, entry in capture['fields'].items():
                path = Path(entry['path'])
                assert sha(path) == entry['sha256'], 'field hash mismatch'
                assert path.stat().st_size == 65536*(2 if field=='wetness' else (8 if field=='foam' else 4))
            for camera in capture['cameras'].values():
                path = Path(camera['image'])
                assert Image.open(path).size == (1280,720)
        result['checks']['repeat_fields'] = {field: first['fields'][field]['sha256'] == second['fields'][field]['sha256'] for field in first['fields']}
        assert all(result['checks']['repeat_fields'].values()), 'repeat state mismatch'
        result['checks']['repeat_effective_profile'] = first['effective_profile'] == second['effective_profile']
        assert result['checks']['repeat_effective_profile'], 'repeat profile mismatch'
        result['checks']['repeat_cameras'] = {key: {k:v for k,v in first['cameras'][key].items() if k!='image'} == {k:v for k,v in second['cameras'][key].items() if k!='image'} for key in first['cameras']}
        assert all(result['checks']['repeat_cameras'].values())
        water = np.fromfile(first['fields']['water']['path'], dtype='<f4').reshape(256,256)
        assert np.isfinite(water).all()
        result['depth_counts'] = {'shallow_002_008': int(((water>=.02)&(water<=.08)).sum()),
                                  'medium_008_020': int(((water>.08)&(water<.2)).sum()),
                                  'deep_ge020': int((water>=.2).sum())}
        result['baseline'] = first
        protected = ['assets/test1_beach/test1_beach_release.json', 'assets/test1_beach/test1_water_front.gdshader',
                     'assets/test1_beach/test1_front_foam_splats.gdshader','assets/test1_beach/test1_bed_lit_fast.gdshader',
                     'scripts/visual/test1_beach_fixed_entry.gd', 'scripts/visual/water_render_staging_entry.gd',
                     'scenes/water_material_natural_candidate/rdc_v1_fixed.tscn','scenes/water_material_natural_candidate/rdc_v1_coupled.tscn']
        result['protected_sources'] = [identity(ROOT/p) for p in protected]
        result['capture_tool'] = identity(ROOT/'tests/water_material_natural/capture.gd')
        result['images'] = [identity(Path(c['image'])) for c in first['cameras'].values()]
        result['pass'] = True
    except Exception as error:
        result['error'] = repr(error)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
    print(json.dumps({'pass': result['pass'], 'checks': result['checks'], 'error': result.get('error'),
                      'depth_counts': result.get('depth_counts')}, ensure_ascii=False))
    return 0 if result['pass'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
