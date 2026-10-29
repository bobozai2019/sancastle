"""Read-only transport/buoyancy resource probe. No managed methods decoded."""
import argparse
import contextlib
import hashlib
import io
import json
import os
import platform
import runpy
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DEPS = ROOT / 'tests/investigation/brush_hit_competitor/deps'
sys.path.insert(0, str(DEPS))
import UnityPy

TARGETS = {'Gravel', 'GravelParticle', 'Dirt', 'DirtParticle', 'Particle',
           'Buoyancy', 'WaterCell', 'ReadbackCell', 'WoodStick', 'WoodenBoat',
           'Boat', 'Bottle'}


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1048576), b''):
            h.update(block)
    return h.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', required=True)
    args = parser.parse_args()
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=False)
    raw_index = []

    def save(name, data):
        (out / name).write_text(json.dumps(data, ensure_ascii=False, indent=2,
                                         default=str), encoding='utf-8')

    def keep(name, raw, source, offset):
        dst = out / 'raw' / name
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(raw)
        raw_index.append({'path': str(dst), 'bytes': len(raw),
                          'sha256': hashlib.sha256(raw).hexdigest(),
                          'source': str(source), 'offset': str(offset)})
        return str(dst)

    data = ROOT / 'sandcastlegame/Sandcastle_Data'
    paths = [ROOT / 'sandcastlegame/GameAssembly.dll',
             data / 'il2cpp_data/Metadata/global-metadata.dat']
    packages = [data / n for n in ['level0', 'sharedassets0.assets',
                                  'resources.assets', 'globalgamemanagers.assets']]
    paths += packages + [data / n for n in ['sharedassets0.assets.resS',
                                          'sharedassets0.resource',
                                          'resources.assets.resS',
                                          'globalgamemanagers.assets.resS']]
    sources = [{'path': str(p), 'bytes': p.stat().st_size, 'sha256': digest(p)}
               for p in paths]
    save('source_manifest.json', sources)
    os.environ['BRUSH_HIT_OUTPUT'] = str(out / 'decoder_baseline')
    decoder = ROOT / 'tests/investigation/brush_hit_competitor/metadata_fields.py'
    with contextlib.redirect_stdout(io.StringIO()):
        n = runpy.run_path(str(decoder))
    mb, bb = n['mb'], n['bb']
    fields = []
    for t in n['types']:
        if t['name'] not in TARGETS or t['namespace'] or not 7300 <= t['index'] <= 7528:
            continue
        row = dict(t, fields=[])
        keep('metadata_type_' + str(t['index']) + '.raw',
             mb[t['offset']:t['offset']+76], n['META'], t['offset'])
        ptr = n['u64'](bb, n['reg']['field_list_offset'] + 8*t['index'])
        fo = n['off'](ptr) if ptr else None
        if fo is not None:
            keep('native_offsets_' + str(t['index']) + '.raw',
                 bb[fo:fo+4*t['field_count']], n['BIN'], fo)
        for j in range(t['field_count']):
            idx = t['first_field'] + j
            pos = n['sections']['fields']['offset'] + 10*idx
            desc = n['describe'](n['u16'](mb, pos+4))
            field = {'index': idx, 'metadata_offset': pos,
                     'name': n['string'](n['i32'](mb, pos)),
                     'type': desc,
                     'native_offset': n['i32'](bb, fo+4*j) if fo is not None else None}
            row['fields'].append(field)
            keep('metadata_field_' + str(idx) + '.raw', mb[pos:pos+10], n['META'], pos)
            do = desc['descriptor_offset']
            keep('native_descriptor_' + str(idx) + '.raw', bb[do:do+16], n['BIN'], do)
        row['parent_type'] = n['describe'](t['parent']) if t['parent'] != 65535 else None
        fields.append(row)
    save('technical_fields.json', fields)
    print(json.dumps({'technical_types': [(t['name'], t['index']) for t in fields]}), flush=True)

    object_rows = []
    inventory = []
    for package in packages:
        env = UnityPy.load(str(package))
        for obj in env.objects:
            if obj.assets_file.name != package.name:
                continue
            typ = obj.type.name
            if typ not in {'MonoScript', 'MonoBehaviour', 'GameObject', 'ComputeShader',
                           'Rigidbody', 'BoxCollider', 'CapsuleCollider', 'SphereCollider',
                           'MeshCollider', 'Transform', 'PhysicMaterial'}:
                continue
            row = {'source': str(package), 'path_id': str(obj.path_id), 'type': typ,
                   'byte_start': str(obj.byte_start), 'byte_size': obj.byte_size,
                   'unity_version': str(obj.assets_file.unity_version)}
            try:
                if typ == 'MonoBehaviour':
                    # The bundled type tree covers the 32-byte engine header only.
                    # This is an explicitly partial read, never a full custom parse.
                    mono = obj.read(check_read=False)
                    script = mono.m_Script.deref().read()
                    row['script_class'] = script.m_ClassName
                    if script.m_ClassName not in TARGETS:
                        continue
                tree = obj.read_typetree(check_read=typ != 'MonoBehaviour')
                row['name'] = tree.get('m_Name', tree.get('m_ClassName', ''))
                if typ == 'ComputeShader' and row['name'] not in {'Gravel', 'Dirt'}:
                    inventory.append(row)
                    continue
                if typ == 'MonoScript' and tree.get('m_ClassName') not in TARGETS:
                    continue
                # Preserve raw physical component/object bytes and the separate readable tree.
                raw = obj.get_raw_data()
                row['raw_path'] = keep(package.name + '_' + str(obj.path_id) + '.raw',
                                       raw, package, obj.byte_start)
                row.update(status='header_only' if typ == 'MonoBehaviour' else 'parsed', tree=tree,
                           external_payload='not extracted; no complete mesh/texture payload claim')
                if typ == 'MonoBehaviour':
                    # UnityPy's native fast reader advances over the whole supplied buffer.
                    # Derive and verify header bounds from its serialized fields instead.
                    name_bytes, = struct.unpack_from('<i', raw, 28)
                    assert name_bytes >= 0 and raw[32:32+name_bytes].decode('utf-8') == tree['m_Name']
                    assert struct.unpack_from('<iq', raw, 0) == (tree['m_GameObject']['m_FileID'], tree['m_GameObject']['m_PathID'])
                    assert struct.unpack_from('<iq', raw, 16) == (tree['m_Script']['m_FileID'], tree['m_Script']['m_PathID'])
                    row['header_bytes'] = (32 + name_bytes + 3) & ~3
                    row['header_bounds_method'] = 'verified serialized PPtrs and aligned UTF8 name length; not native reader cursor'
                    row['custom_tail_bytes'] = obj.byte_size - row['header_bytes']
            except Exception as error:
                row.update(status='parse_failed', error=repr(error))
                if typ != 'MonoBehaviour':
                    row['raw_path'] = keep(package.name+'_'+str(obj.path_id)+'.raw',
                                           obj.get_raw_data(), package, obj.byte_start)
            object_rows.append(row)
    save('physical_objects.json', object_rows)
    save('compute_inventory.json', inventory)
    save('raw_index.json', raw_index)
    after = [{'path': str(p), 'bytes': p.stat().st_size, 'sha256': digest(p)} for p in paths]
    save('source_after.json', after)
    save('manifest.json', {'python': platform.python_version(), 'unitypy': UnityPy.__version__,
                          'script': str(Path(__file__).resolve()),
                          'script_sha256': digest(Path(__file__)),
                          'decoder': str(decoder), 'decoder_sha256': digest(decoder),
                          'command': 'python ' + str(Path(__file__).resolve()) + ' --out ' + str(out),
                          'source_unchanged': sources == after, 'raw_records': len(raw_index),
                          'objects': len(object_rows),
                          'scope': 'selected physical types/fields, serialized physical components, Gravel/Dirt compute; no methods or business behavior decoded'})
    print(json.dumps({'output': str(out), 'objects': len(object_rows),
                      'raw_records': len(raw_index), 'source_unchanged': sources == after}))


if __name__ == '__main__':
    main()
