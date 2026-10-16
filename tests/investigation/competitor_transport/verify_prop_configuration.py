"""Recheck selected buoyancy resources, without executing/decompiling game methods."""
import argparse
import hashlib
import json
import platform
import struct
import sys
from pathlib import Path


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    root, out = args.root.resolve(), args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    historical = root / 'test_output/competitor_transport_20261012'
    inventory = read_json(root / 'docs/competitor/transport_evidence_inventory.json')
    report = {'schema_version': 1, 'date': '2026-10-15',
              'scope': 'Selected package field/byte checks only; no runtime forces, contacts or temporal proof',
              'python': platform.python_version(), 'command': sys.argv,
              'script_sha256': digest(Path(__file__)), 'sources': [], 'artifacts': [],
              'objects': [], 'props': [], 'errors': []}
    try:
        for item in inventory['sources']:
            if Path(item['path']).name not in ('sharedassets0.assets', 'GameAssembly.dll', 'global-metadata.dat'):
                continue
            path = Path(item['path'])
            actual = {'path': str(path), 'bytes': path.stat().st_size, 'sha256': digest(path)}
            actual['matches'] = actual['sha256'] == item['sha256'] and actual['bytes'] == item.get('bytes', item.get('size'))
            report['sources'].append(actual)
            if not actual['matches']:
                raise ValueError('source identity mismatch: ' + str(path))
        for suffix in ('physical_objects.json', 'raw_index.json', 'technical_fields.json', 'buoyancy_config.json'):
            expected = next(x for x in inventory['current_evidence'] if x['path'].endswith(suffix))
            path = Path(expected['path'])
            actual = {'path': str(path), 'bytes': path.stat().st_size, 'sha256': digest(path)}
            actual['matches'] = actual['sha256'] == expected['sha256'] and actual['bytes'] == expected['bytes']
            report['artifacts'].append(actual)
            if not actual['matches']:
                raise ValueError('historical artifact changed: ' + str(path))
        objects = read_json(historical / 'package_v4/physical_objects.json')
        objects = {x['path_id']: x for x in objects if Path(x['source']).name == 'sharedassets0.assets'}
        raw_index = {Path(x['path']).name: x for x in read_json(historical / 'package_v4/raw_index.json')}
        configs = read_json(historical / 'analysis_v4/buoyancy_config.json')
        checked = set()

        def check_object(path_id):
            obj = objects[str(path_id)]
            path = Path(obj['raw_path'])
            raw = path.read_bytes()
            index = raw_index[path.name]
            with Path(index['source']).open('rb') as stream:
                stream.seek(int(index['offset']))
                original = stream.read(index['bytes'])
            if len(raw) != index['bytes'] or hashlib.sha256(raw).hexdigest() != index['sha256'] or raw != original:
                raise ValueError('raw/source mismatch: ' + str(path))
            if str(path_id) not in checked:
                report['objects'].append({'path_id': str(path_id), 'type': obj['type'],
                    'source': index['source'], 'offset': int(index['offset']), 'bytes': len(raw),
                    'raw_path': str(path), 'sha256': index['sha256'], 'matches_source_range': True})
                checked.add(str(path_id))
            return obj, raw

        collider_ids = {'WoodStick': [5091, 5467], 'Bottle': [5449],
                        'WoodenBoat': [5471, 5457], 'Boat': [5448]}
        for config in configs:
            name = config['game_object']
            if name not in collider_ids:
                continue
            _, raw = check_object(config['path_id'])
            file_id, rb_id = struct.unpack_from('<iq', raw, 32)
            count, = struct.unpack_from('<i', raw, 44)
            threshold, = struct.unpack_from('<f', raw, 48 + 12 * count)
            point_ids = [struct.unpack_from('<iq', raw, 48 + 12 * i) for i in range(count)]
            if file_id != 0 or rb_id != int(config['rigidbody_path_id']) or count != len(config['points']) or len(raw) != 52 + 12 * count:
                raise ValueError('buoyancy layout mismatch: ' + name)
            if threshold != config['buried_threshold'] or point_ids != [(p['file_id'], p['path_id']) for p in config['points']]:
                raise ValueError('buoyancy values mismatch: ' + name)
            rb, rb_raw = check_object(rb_id)
            mass, linear_damp, angular_damp, cx, cy, cz = struct.unpack_from('<6f', rb_raw, 12)
            tree = rb['tree']
            if [mass, linear_damp, angular_damp, cx, cy, cz] != [tree['m_Mass'], tree['m_LinearDamping'], tree['m_AngularDamping'], *[tree['m_CenterOfMass'][k] for k in ('x', 'y', 'z')]]:
                raise ValueError('rigidbody scalar mismatch: ' + name)
            for point in config['points']:
                check_object(point['path_id'])
                check_object(point['parent']['m_PathID'])
            colliders = []
            for collider_id in collider_ids[name]:
                collider, _ = check_object(collider_id)
                colliders.append({'path_id': str(collider_id), 'type': collider['type'], 'tree': collider['tree']})
            report['props'].append({'name': name, 'buoyancy_path_id': config['path_id'],
                'rigidbody_path_id': str(rb_id), 'point_count': count, 'points': config['points'],
                'buried_threshold': threshold, 'mass': mass, 'linear_damping': linear_damp,
                'angular_damping': angular_damp, 'center_of_mass_local': [cx, cy, cz],
                'colliders': colliders,
                'selectors': {'buoyancy': config['field_selectors'], 'rigidbody_mass_damping_com_bytes': [12, 36]},
                'limits': 'Package defaults/local coordinates; scale-to-volume, SI scale, runtime overrides and methods unknown'})
    except Exception as exc:
        report['errors'].append(type(exc).__name__ + ': ' + str(exc))
    report['result'] = 'PASS' if not report['errors'] and len(report['props']) == 4 else 'FAIL'
    (out / 'configuration_check.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (out / Path(__file__).name).write_bytes(Path(__file__).read_bytes())
    print(json.dumps({'result': report['result'], 'sources': len(report['sources']),
                      'objects': len(report['objects']), 'props': len(report['props']), 'errors': report['errors']}))
    raise SystemExit(report['result'] != 'PASS')


if __name__ == '__main__':
    main()
