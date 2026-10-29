"""Audit byte provenance, bound-buffer identities and physical config references."""
import hashlib
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
RUN = ROOT / 'test_output/competitor_transport_20261012'
PACKAGE = RUN / 'package_v4'
ANALYSIS = RUN / 'analysis_v4'
REPLAY = RUN / 'replay_v2'
MAPPING = RUN / 'readback_mapping_v2'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def read(p):
    return json.loads(p.read_text(encoding='utf-8-sig'))


def main():
    sources = read(PACKAGE / 'source_manifest.json')
    content = {x['path']: Path(x['path']).read_bytes() for x in sources}
    assert all(len(content[x['path']]) == x['bytes'] and sha(content[x['path']]) == x['sha256']
               for x in sources)
    raw_index = read(PACKAGE / 'raw_index.json')
    for row in raw_index:
        raw = Path(row['path']).read_bytes()
        assert len(raw) == row['bytes'] and sha(raw) == row['sha256']
        pos = int(row['offset'])
        assert raw == content[row['source']][pos:pos+len(raw)]
    shaders = read(ANALYSIS / 'shader_index.json')
    for row in shaders:
        raw = Path(row['file']).read_bytes()
        assert len(raw) == row['bytes'] and sha(raw) == row['sha256']
        assert all(content[row['source']][int(pos):int(pos)+len(raw)] == raw
                   for pos in row['source_byte_offset_candidates'])
    replay = read(REPLAY / 'manifest.json')
    assert replay['found'] and replay['source_unchanged'] and replay['event'] == 1566
    assert sha(Path(replay['source']['path']).read_bytes()) == replay['source']['sha256']
    for row in replay['exports']:
        raw = Path(row['path']).read_bytes()
        assert len(raw) == row['size'] and sha(raw) == row['sha256']
    target = next(x for x in shaders if x['name'] == 'Gravel_Update_0')
    assert sha((REPLAY / 'gravel_update.dxbc').read_bytes()) == target['sha256']
    mapping = read(MAPPING / 'index.json')
    raw = (MAPPING / 'object.raw').read_bytes()
    assert sha(raw) == mapping['object_sha256']
    pos = mapping['byte_start']
    assert content[mapping['source']][pos:pos+len(raw)] == raw
    code = (MAPPING / 'update.dxbc').read_bytes()
    assert sha(code) == mapping['code_sha256']
    assert all(raw[pos:pos+len(code)] == code for pos in mapping['code_offsets'])
    cb = (REPLAY / 'cb0.raw').read_bytes()
    args = struct.unpack('<5I', (REPLAY / 'readwrite_0.raw').read_bytes())
    alive = struct.unpack('<32768i', (REPLAY / 'readwrite_1.raw').read_bytes())[:args[1]]
    assert len(set(alive)) == 344 and all(0 <= i < 32768 for i in alive)
    assert struct.unpack_from('<2i', cb, 2240) == (1024, 512)
    assert struct.unpack_from('<2i', cb, 2272) == (512, 256)
    tools = ['probe_transport.py', 'analyze_transport.py', 'extract_readback_mapping.py',
             'replay_gravel.py', 'verify_transport.py']
    for name in tools:
        (RUN / name).write_bytes((Path(__file__).parent / name).read_bytes())
    summary = {'pass': True, 'raw_records_checked': len(raw_index),
               'source_files_checked': len(sources)+1, 'package_shader_variants': len(shaders),
               'capture_event': 1566, 'active_particles': 344,
               'scope': 'byte provenance, package/runtime bytecode identity, field/pointer decoding only; no continuous-motion or float-force test',
               'known_partial_attempts': {
                   'package_v1': 'default MonoBehaviour full parse failed; unscoped duplicate Particle type included',
                   'package_v2/package_v3': 'native fast reader cursor did not delimit engine header; corrected in v4',
                   'analysis_v1/analysis_v2': 'header-bound assertion failures; no semantic pass',
                   'analysis_v3': 'duplicate bytecode occurrences invalidated unique-offset assertion; exact tree selector and all occurrences retained in v4',
                   'replay_v1': 'helper did not create manifest; setup failure and own-process termination recorded; no replay success claim',
                   'readback_mapping_v1': 'inline preliminary export; reproducible script export is v2'}}
    (RUN / 'verification.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
    items = []
    for p in RUN.rglob('*'):
        if p.is_file() and p.name != 'artifact_index.json':
            raw = p.read_bytes()
            items.append({'path': str(p), 'bytes': len(raw), 'sha256': sha(raw)})
    (RUN / 'artifact_index.json').write_text(json.dumps(items, indent=2), encoding='utf-8')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
