"""Decode only Buoyancy resource configuration and package compute instructions."""
import argparse
import ctypes
import hashlib
import json
import struct
from pathlib import Path


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def disassemble(raw):
    dll = ctypes.WinDLL('d3dcompiler_47.dll')
    fn = dll.D3DDisassemble
    fn.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint,
                   ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
    fn.restype = ctypes.c_long
    src = ctypes.create_string_buffer(raw)
    blob = ctypes.c_void_p()
    hr = fn(src, len(raw), 0, None, ctypes.byref(blob))
    if hr < 0:
        raise RuntimeError('D3DDisassemble HRESULT ' + hex(hr & 0xffffffff))
    vt = ctypes.cast(blob, ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
    get_ptr = ctypes.WINFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p)(vt[3])
    get_size = ctypes.WINFUNCTYPE(ctypes.c_size_t, ctypes.c_void_p)(vt[4])
    release = ctypes.WINFUNCTYPE(ctypes.c_ulong, ctypes.c_void_p)(vt[2])
    try:
        return ctypes.string_at(get_ptr(blob), get_size(blob)).rstrip(b'\0').decode('utf-8')
    finally:
        release(blob)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--package', required=True)
    parser.add_argument('--out', required=True)
    a = parser.parse_args()
    package = Path(a.package).resolve()
    out = Path(a.out).resolve()
    out.mkdir(exist_ok=False, parents=True)
    objects = json.loads((package / 'physical_objects.json').read_text(encoding='utf-8'))
    fields = json.loads((package / 'technical_fields.json').read_text(encoding='utf-8'))
    rows = {('sharedassets0.assets', x['path_id']): x for x in objects
            if Path(x['source']).name == 'sharedassets0.assets'}
    index = []
    def save(name, data):
        (out / name).write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')

    # Only the public serialized prefix (rb, points, threshold) is decoded.
    buoy_type = next(t for t in fields if t['name'] == 'Buoyancy')
    assert [(f['name'], f['type']['name']) for f in buoy_type['fields'][:3]] == [
        ('rb', 'UnityEngine.Rigidbody'), ('samplingPoints', 'UnityEngine.Transform[]'),
        ('buriedThreshold', 'float')]
    assert all(f['type']['attrs'] & 7 == 6 for f in buoy_type['fields'][:3])
    buoy = []
    for obj in objects:
        if obj.get('script_class') != 'Buoyancy':
            continue
        raw = Path(obj['raw_path']).read_bytes()
        assert obj['header_bytes'] == 32
        file_id, rb_id = struct.unpack_from('<iq', raw, 32)
        count, = struct.unpack_from('<i', raw, 44)
        assert 0 < count < 32 and len(raw) == 52 + 12*count
        points = [dict(zip(['file_id', 'path_id'], struct.unpack_from('<iq', raw, 48+12*i)))
                  for i in range(count)]
        threshold, = struct.unpack_from('<f', raw, 48+12*count)
        assert file_id == 0 and all(p['file_id'] == 0 for p in points)
        rb = rows[('sharedassets0.assets', str(rb_id))]
        assert rb['type'] == 'Rigidbody'
        go = rows[('sharedassets0.assets', str(obj['tree']['m_GameObject']['m_PathID']))]
        assert go['type'] == 'GameObject'
        decoded_points = []
        for p in points:
            transform = rows[('sharedassets0.assets', str(p['path_id']))]
            assert transform['type'] == 'Transform'
            tree = transform['tree']
            point_go = rows[('sharedassets0.assets', str(tree['m_GameObject']['m_PathID']))]
            decoded_points.append(dict(p, name=point_go['name'], position=tree['m_LocalPosition'],
                                       scale=tree['m_LocalScale'], rotation=tree['m_LocalRotation'],
                                       parent=tree['m_Father']))
        components = []
        for component in go['tree']['m_Component']:
            pp = component['component']
            entry = rows.get(('sharedassets0.assets', str(pp['m_PathID'])))
            if entry:
                components.append({'path_id': str(pp['m_PathID']), 'type': entry['type'],
                                   'script_class': entry.get('script_class')})
        buoy.append({'source': obj['source'], 'path_id': obj['path_id'],
                     'raw_path': obj['raw_path'], 'raw_sha256': sha(raw),
                     'game_object': go['name'], 'game_object_path_id': go['path_id'],
                     'rigidbody_path_id': str(rb_id), 'rigidbody': rb['tree'],
                     'points': decoded_points, 'buried_threshold': threshold,
                     'field_selectors': {'rb': [32, 12], 'point_count': [44, 4],
                                         'point_array': [48, 12*count],
                                         'buriedThreshold': [48+12*count, 4]},
                     'components': components,
                     'status': 'full_serialized_buoyancy_object; runtime caches not serialized'})
    save('buoyancy_config.json', buoy)

    for obj in objects:
        if obj['type'] != 'ComputeShader':
            continue
        original = Path(obj['raw_path']).read_bytes()
        for vi, variant in enumerate(obj['tree']['variants']):
            # Renderer 2 is the package DXBC variant; others remain indexed in package.
            if variant['targetRenderer'] != 2:
                continue
            for ki, kernel in enumerate(variant['kernels']):
                for ui, unique in enumerate(kernel['uniqueVariants']):
                    code = bytes(unique['code'])
                    assert code[:4] == b'DXBC'
                    start = original.find(code)
                    assert start >= 0
                    occurrences = []
                    while start >= 0:
                        occurrences.append(start)
                        start = original.find(code, start+1)
                    stem = obj['name'] + '_' + kernel['name'] + '_' + str(ui)
                    (out / (stem+'.dxbc')).write_bytes(code)
                    text = disassemble(code)
                    (out / (stem+'.txt')).write_text(text, encoding='utf-8')
                    cb = [variant['constantBuffers'][idx] for idx in unique['cbVariantIndices']]
                    record = {'name': stem, 'source': obj['source'], 'path_id': obj['path_id'],
                              'selector': f'variants[{vi}].kernels[{ki}].uniqueVariants[{ui}]',
                              'source_byte_offset_candidates': [str(int(obj['byte_start']) + start) for start in occurrences],
                              'object_relative_offset_candidates': occurrences,
                              'offset_status': 'unique' if len(occurrences) == 1 else 'duplicate bytecode occurrences; tree selector is exact',
                              'bytes': len(code), 'sha256': sha(code),
                              'thread_group': unique['threadGroupSize'],
                              'bindings': {k: unique[k] for k in ['cbs', 'inBuffers', 'outBuffers', 'textures']},
                              'constant_buffers': cb, 'disassembly_sha256': sha(text.encode()),
                              'file': str(out / (stem+'.dxbc'))}
                    index.append(record)
    save('shader_index.json', index)
    save('manifest.json', {'package': str(package), 'script': str(Path(__file__).resolve()),
                          'script_sha256': sha(Path(__file__).read_bytes()),
                          'd3dcompiler_path': 'C:/Windows/System32/d3dcompiler_47.dll',
                          'd3dcompiler_sha256': sha(Path('C:/Windows/System32/d3dcompiler_47.dll').read_bytes()),
                          'buoyancy_objects': len(buoy), 'shader_variants': len(index),
                          'scope': 'serialized Buoyancy prefix verified against fields and pointers; Gravel/Dirt DXBC; no CPU methods or business code decoded'})
    print(json.dumps({'buoyancy_objects': len(buoy), 'shader_variants': len(index),
                      'props': [(x['game_object'], len(x['points']), x['buried_threshold'])
                                for x in buoy]}, ensure_ascii=False))


if __name__ == '__main__':
    main()
