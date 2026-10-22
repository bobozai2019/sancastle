"""Read-only Plant visual-resource probe; no gameplay methods or call chains.

Preserves selected original object bytes, external payloads, and field metadata.
The inherited version-39 decoder is executed only through its helper definitions.
"""
import argparse
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import platform
import struct
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tests/investigation/brush_hit_competitor/deps'))
import UnityPy


def identity(path):
    return dict(path=str(path), bytes=path.stat().st_size,
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    data = ROOT / 'sandcastlegame/Sandcastle_Data'
    sources = [data / n for n in ('level0', 'sharedassets0.assets',
               'sharedassets0.assets.resS', 'globalgamemanagers.assets')]
    sources += [ROOT / 'sandcastlegame/GameAssembly.dll',
                data / 'il2cpp_data/Metadata/global-metadata.dat']
    report = dict(scope='Plant visual configuration and GPU bytecode; no gameplay methods, live bindings or temporal observation',
                  python=platform.python_version(), unitypy=UnityPy.__version__,
                  command=sys.argv, tool=identity(Path(__file__).resolve()),
                  sources=[identity(p) for p in sources], objects=[], fields=[],
                  plants=[], kernels=[], artifacts=[], errors=[])

    def save(name, value):
        path = out / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        return path

    def keep(name, raw, selector):
        path = out / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw)
        row = dict(identity(path), selector=selector)
        report['artifacts'].append(row)
        return row

    kept = {}

    def keep_object(obj):
        key = (obj.assets_file.name, obj.path_id)
        if key in kept:
            return kept[key]
        source = data / key[0]
        raw = obj.get_raw_data()
        with source.open('rb') as stream:
            stream.seek(obj.byte_start)
            assert stream.read(obj.byte_size) == raw
        header_only = obj.type.name == 'MonoBehaviour'
        tree = obj.read_typetree(check_read=not header_only)
        name = tree.get('m_Name', '')
        stem = 'objects/' + key[0] + '_' + str(key[1])
        record = dict(source=str(source), path_id=key[1], type=obj.type.name,
                      name=name, offset=obj.byte_start, bytes=obj.byte_size,
                      unity_version=str(obj.assets_file.unity_version),
                      parse='header_only' if header_only else 'complete_typetree')
        record['raw'] = keep(stem + '.raw', raw, dict(source=str(source),
                            offset=obj.byte_start, bytes=obj.byte_size, path_id=key[1]))
        # GPU blobs are preserved separately; avoid large numeric arrays in JSON.
        readable = dict(tree)
        for field in ('compressedBlob', 'image data', 'm_ImageData'):
            if field in readable:
                readable[field] = {'omitted_from_json': True, 'retained_in_raw': True}
        if obj.type.name == 'ComputeShader':
            readable = {'m_Name': name, 'variant_count': len(tree['variants'])}
        record['tree'] = str(save(stem + '.json', readable))
        for field in ('m_StreamData', 'm_StreamingInfo'):
            stream_info = tree.get(field)
            if not stream_info or not stream_info.get('size'):
                continue
            source_payload = data / Path(stream_info['path']).name
            offset, size = int(stream_info['offset']), int(stream_info['size'])
            with source_payload.open('rb') as stream:
                stream.seek(offset)
                payload = stream.read(size)
            assert len(payload) == size
            record['external_payload'] = keep(stem + '.payload', payload,
                  dict(source=str(source_payload), offset=offset, bytes=size, field=field))
        report['objects'].append(record)
        kept[key] = (tree, raw, record)
        return kept[key]

    try:
        decoder = ROOT / 'tests/investigation/brush_hit_competitor/metadata_fields.py'
        helpers = decoder.read_text(encoding='utf-8').split('selected=[]')[0]
        assert 'def describe(idx)' in helpers and 'targets=' not in helpers
        report['metadata_decoder'] = dict(identity(decoder), execution_scope='helper prefix before selected=[]; no methods decoded')
        os.environ['BRUSH_HIT_OUTPUT'] = str(out / 'metadata_helpers')
        ns = {'__name__': 'vegetation_metadata_helpers'}
        with contextlib.redirect_stdout(io.StringIO()):
            exec(compile(helpers, str(decoder), 'exec'), ns)
        for typ in ns['types']:
            if typ['name'] not in {'Plant', 'PlantParticle', 'Particle', 'Compute'} or typ['namespace']:
                continue
            row = dict(typ, fields=[])
            keep('metadata/type_' + str(typ['index']) + '.raw',
                 ns['mb'][typ['offset']:typ['offset']+76],
                 dict(source=str(ns['META']), offset=typ['offset'], bytes=76))
            ptr = ns['u64'](ns['bb'], ns['reg']['field_list_offset'] + 8*typ['index'])
            offset = ns['off'](ptr) if ptr else None
            if offset is not None:
                keep('metadata/offsets_' + str(typ['index']) + '.raw',
                     ns['bb'][offset:offset+4*typ['field_count']],
                     dict(source=str(ns['BIN']), offset=offset, bytes=4*typ['field_count']))
            for j in range(typ['field_count']):
                idx = typ['first_field'] + j
                pos = ns['sections']['fields']['offset'] + 10*idx
                desc = ns['describe'](ns['u16'](ns['mb'], pos+4))
                field = dict(index=idx, metadata_offset=pos,
                             name=ns['string'](ns['i32'](ns['mb'], pos)), type=desc,
                             native_offset=ns['i32'](ns['bb'], offset+4*j) if offset else None)
                row['fields'].append(field)
                keep('metadata/field_' + str(idx) + '.raw', ns['mb'][pos:pos+10],
                     dict(source=str(ns['META']), offset=pos, bytes=10))
                pos = desc['descriptor_offset']
                keep('metadata/descriptor_' + str(idx) + '.raw', ns['bb'][pos:pos+16],
                     dict(source=str(ns['BIN']), offset=pos, bytes=16))
            row['parent_type'] = ns['describe'](typ['parent'])
            report['fields'].append(row)
        env = UnityPy.load(str(data / 'level0'))
        objects = {o.path_id: o for o in env.objects if o.assets_file.name == 'level0'}
        for obj in objects.values():
            if obj.type.name != 'MonoBehaviour':
                continue
            mono = obj.read(check_read=False)
            script = mono.m_Script.deref()
            if script.read().m_ClassName != 'Plant':
                continue
            keep_object(script)
            header, raw, record = keep_object(obj)
            go, _, _ = keep_object(mono.m_GameObject.deref())
            assert len(raw) == 100 and struct.unpack_from('<i', raw, 28)[0] == 0
            refs = {name: struct.unpack_from('<iq', raw, offset)
                    for name, offset in [('compute',32),('mesh',48),('material',60)]}
            assert all(fid == 2 for fid, pid in refs.values())
            plant = dict(name=go['m_Name'], path_id=obj.path_id,
                         game_object=header['m_GameObject'], active_self=go['m_IsActive'],
                         capacity=struct.unpack_from('<i',raw,44)[0],
                         cast_shadows=bool(struct.unpack_from('<I',raw,72)[0]),
                         size_range=struct.unpack_from('<2f',raw,76),
                         ground_height_range=struct.unpack_from('<2f',raw,84),
                         fertility_range=struct.unpack_from('<2f',raw,92), references=refs,
                         selectors={'compute':[32,44], 'capacity':[44,48], 'mesh':[48,60],
                                    'material':[60,72], 'cast_shadows':[72,76],
                                    'size_range':[76,84], 'ground_height_range':[84,92],
                                    'fertility_range':[92,100]})
            # Traverse only Transform ancestors, recording parent activation and layout.
            transform_ref = go['m_Component'][0]['component']
            transform = objects[transform_ref['m_PathID']]
            ancestors = []
            while transform:
                tt, _, _ = keep_object(transform)
                parent_go, _, _ = keep_object(objects[tt['m_GameObject']['m_PathID']])
                ancestors.append(dict(name=parent_go['m_Name'], active_self=parent_go['m_IsActive'],
                                      transform=transform.path_id))
                pid = tt['m_Father']['m_PathID']
                transform = objects[pid] if pid else None
            plant['ancestors_including_self'] = ancestors
            plant['active_in_packaged_hierarchy'] = all(a['active_self'] for a in ancestors)
            report['plants'].append(plant)
        asset_env = UnityPy.load(str(data / 'sharedassets0.assets'))
        assets = {o.path_id:o for o in asset_env.objects if o.assets_file.name=='sharedassets0.assets'}
        for plant in report['plants']:
            for field in ('mesh','material','compute'):
                keep_object(assets[plant['references'][field][1]])
            mat, _, _ = kept[('sharedassets0.assets', plant['references']['material'][1])]
            plant['material_name'] = mat['m_Name']
            shader = assets[mat['m_Shader']['m_PathID']]
            st, _, _ = keep_object(shader)
            plant['shader_name'] = st['m_ParsedForm']['m_Name']
            plant['atlas'] = []
            for name, settings in mat['m_SavedProperties']['m_TexEnvs']:
                pid = settings['m_Texture']['m_PathID']
                if not pid:
                    continue
                texture = assets[pid]
                tt, _, rec = keep_object(texture)
                plant['atlas'].append(dict(property=name, path_id=pid,
                      name=tt['m_Name'], width=tt['m_Width'], height=tt['m_Height'],
                      scale=settings['m_Scale']))
                if plant['name'] in {'Kelp','SeaGrass','BuffaloGrass','SwitchGrass','WheatGrass','GreyTussock'}:
                    preview = out / 'previews' / (plant['name'] + '.png')
                    preview.parent.mkdir(exist_ok=True)
                    image = texture.read().image
                    image.thumbnail((1024,1024))
                    image.save(preview)
                    report['artifacts'].append(dict(identity(preview),selector=dict(derived_from=rec['raw']['path'], operation='UnityPy texture decode; thumbnail max1024')))
        analyzer = ROOT / 'tests/investigation/competitor_transport/analyze_transport.py'
        spec = importlib.util.spec_from_file_location('transport_disasm', analyzer)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        report['disassembler_helper'] = identity(analyzer)
        tree, raw, _ = kept[('sharedassets0.assets',650)]
        for vi, variant in enumerate(tree['variants']):
            if variant['targetRenderer'] != 2:
                continue
            for ki, kernel in enumerate(variant['kernels']):
                for ui, unique in enumerate(kernel['uniqueVariants']):
                    code = bytes(unique['code'])
                    start = raw.find(code)
                    assert start >= 0 and code[:4] == b'DXBC'
                    stem = f"compute/{kernel['name']}_{vi}_{ui}"
                    selector = dict(source=str(data/'sharedassets0.assets'), path_id=650,
                                    offset_in_object=start, bytes=len(code), variant=vi,kernel=ki,unique_variant=ui)
                    bytecode = keep(stem+'.dxbc',code,selector)
                    assembly = keep(stem+'.asm',module.disassemble(code).encode('utf-8'),dict(derived_from=bytecode['path'],tool='D3DDisassemble d3dcompiler_47.dll'))
                    report['kernels'].append(dict(name=kernel['name'],variant=vi,unique_variant=ui,
                          thread_group=unique['threadGroupSize'],bytecode=bytecode,assembly=assembly,
                          bindings={k:unique[k] for k in ('inBuffers','outBuffers','textures','cbs')},
                          constant_buffers=[variant['constantBuffers'][i] for i in unique['cbVariantIndices']]))
        compiler = Path(os.environ.get('WINDIR','C:/Windows')) / 'System32/d3dcompiler_47.dll'
        report['d3dcompiler'] = identity(compiler)
        report['source_after'] = [identity(p) for p in sources]
        assert report['source_after'] == report['sources']
    except Exception as exc:
        report['errors'].append(type(exc).__name__ + ': ' + str(exc))
    report['result'] = 'PASS_STATIC_EXPORT' if not report['errors'] else 'PARTIAL_EXPORT'
    save('manifest.json',report)
    print(json.dumps(dict(result=report['result'], plants=len(report['plants']),objects=len(report['objects']),kernels=len(report['kernels']),errors=report['errors'])))
    return bool(report['errors'])


if __name__ == '__main__':
    raise SystemExit(main())
