"""Decode locally supplied Plant assets; keep source bytes and mappings verifiable.

No gameplay code is read. RGBA atlas alpha is depth, not conventional opacity.
"""
import hashlib
import json
from pathlib import Path
import platform
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/investigation/brush_hit_competitor/deps'))
import UnityPy
from UnityPy.helpers.MeshHelper import MeshHandler

KINDS = [('seagrass', 'SeaGrass'), ('kelp', 'Kelp'), ('shore_grass', 'BuffaloGrass'),
         ('dune_grass', 'GreyTussock'), ('red_algae', 'RedAlgae'),
         ('switch_grass', 'SwitchGrass'), ('wheat_grass', 'WheatGrass'),
         ('yarrow', 'Yarrow'), ('goldenrod', 'Goldenrod')]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    evidence = ROOT / 'docs/competitor/evidence/vegetation_20261021/package_v2'
    previous = json.loads((evidence / 'manifest.json').read_text('utf-8'))
    source = ROOT / 'sandcastlegame/Sandcastle_Data/sharedassets0.assets'
    payload = source.with_suffix('.assets.resS')
    for p in (source, payload):
        expected = next(s for s in previous['sources'] if Path(s['path']).name == p.name)
        assert sha(p) == expected['sha256'], p
    env = UnityPy.load(str(source))
    objects = {o.path_id: o for o in env.objects if o.assets_file.name == source.name}
    out = ROOT / 'assets/vegetation/competitor'
    out.mkdir(parents=True, exist_ok=True)
    manifest = {'tool': 'tools/vegetation/import_competitor.py', 'tool_sha256': sha(Path(__file__)),
                'command': [sys.executable, '-X', 'utf8', str(Path(__file__).resolve())],
                'python': platform.python_version(), 'unitypy': UnityPy.__version__,
                'sources': [s for s in previous['sources'] if Path(s['path']).name in (source.name, payload.name)],
                'scope': 'Nine visual Plant atlases and proxy meshes. No gameplay methods.',
                'license': 'Extracted from user-supplied proprietary competitor package; no redistribution license established.',
                'assets': []}
    for kind, name in KINDS:
        plant = next(p for p in previous['plants'] if p['name'] == name)
        mid = plant['references']['mesh'][1]
        tid = plant['atlas'][0]['path_id']
        matid = plant['references']['material'][1]
        selectors = []
        for pid in (mid, tid, matid):
            obj = objects[pid]
            old = next(o for o in previous['objects'] if o['path_id'] == pid and o['source'].endswith(source.name))
            raw = obj.get_raw_data()
            assert hashlib.sha256(raw).hexdigest() == old['raw']['sha256']
            selectors.append({'container': source.name, 'path_id': pid, 'offset': obj.byte_start,
                              'bytes': obj.byte_size, 'sha256': hashlib.sha256(raw).hexdigest(),
                              'evidence': 'docs/competitor/evidence/vegetation_20261021/package_v2/objects/' + source.name + '_' + str(pid) + '.raw'})
        tex = objects[tid].read()
        tex.image.save(out / (kind + '_atlas.png'))
        mesh = objects[mid].read()
        external = next(o for o in previous['objects'] if o['path_id'] == mid and o['type'] == 'Mesh').get('external_payload')
        if external:
            selector = external['selector']
            with Path(selector['source']).open('rb') as stream:
                stream.seek(selector['offset'])
                assert hashlib.sha256(stream.read(selector['bytes'])).hexdigest() == external['sha256']
            assert sha(Path(external['path'])) == external['sha256']
        handler = MeshHandler(mesh); handler.process()
        triangles = [t for part in handler.get_triangles() for t in part]
        material = objects[matid].read_typetree()
        pivot = dict(material['m_SavedProperties']['m_Colors'])['pivotOffset']
        pivot = [pivot[k] for k in ('r', 'g', 'b', 'a')]
        value = {'kind': kind, 'source_name': name, 'vertices': handler.m_Vertices,
                 'normals': handler.m_Normals, 'triangles': triangles, 'pivot': pivot,
                 'atlas_grid': int(plant['atlas'][0]['scale']['x'])}
        path = out / (kind + '_proxy.json')
        path.write_text(json.dumps(value, indent=2) + '\n', 'utf-8', newline='\n')
        manifest['assets'].append({'kind': kind, 'source_name': name, 'plant_path_id': plant['path_id'],
            'default_active': plant['active_in_packaged_hierarchy'], 'selectors': selectors,
            'pivot': pivot, 'atlas_grid': value['atlas_grid'], 'texture_color_space': tex.m_ColorSpace,
            'vertices': len(handler.m_Vertices), 'triangles': len(triangles),
            'external_mesh_payload': external,
            'outputs': [{'path': p.relative_to(ROOT).as_posix(), 'bytes': p.stat().st_size, 'sha256': sha(p)} for p in (path, out / (kind + '_atlas.png'))]})
        print(kind, 'height', max(v[1] for v in handler.m_Vertices), 'pivot', pivot)
    for p in (source, payload):
        assert sha(p) == next(s for s in manifest['sources'] if Path(s['path']).name == p.name)['sha256']
    (out / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', 'utf-8', newline='\n')


if __name__ == '__main__':
    main()
