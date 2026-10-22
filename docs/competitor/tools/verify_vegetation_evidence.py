"""Verify retained Plant evidence against original source ranges and seal the index."""
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'docs/competitor/evidence/vegetation_20261021'
OUT = ROOT / 'docs/competitor/vegetation_sources_20261021.json'


def identity(path):
    return dict(path=str(path.resolve()), bytes=path.stat().st_size,
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def load(path):
    return json.loads(path.read_text(encoding='utf8'))


def main():
    names = ('package_v1','package_v2','shader_v1')
    manifests = {n:load(BASE/n/'manifest.json') for n in names}
    sources = manifests['package_v2']['sources']
    source_bytes = {}
    for expected in sources:
        path = Path(expected['path'])
        assert identity(path)==expected
        source_bytes[str(path)] = path.read_bytes()
    artifacts, ranges, embedded = 0, 0, 0
    for name, manifest in manifests.items():
        object_offsets = {(x['source'],x['path_id']):x['offset'] for x in manifest.get('objects',[])}
        for artifact in manifest['artifacts']:
            selector = artifact['selector']
            if 'source' in selector and 'path_id' in selector and 'offset' in selector:
                object_offsets[(selector['source'],selector['path_id'])] = selector['offset']
        for artifact in manifest['artifacts']:
            path = Path(artifact['path'])
            actual = identity(path)
            assert all(actual[k]==artifact[k] for k in ('path','bytes','sha256')), path
            artifacts += 1
            selector = artifact['selector']
            source = selector.get('source')
            if source and 'offset' in selector:
                start = selector['offset']
                assert path.read_bytes()==source_bytes[source][start:start+actual['bytes']], path
                ranges += 1
            elif source and 'offset_in_object' in selector:
                start = object_offsets[(source,selector['path_id'])]+selector['offset_in_object']
                assert path.read_bytes()==source_bytes[source][start:start+actual['bytes']], path
                ranges += 1
            elif 'offset_in_decompressed' in selector:
                blob=(BASE/name/'decompressed.bin').read_bytes()
                start=selector['offset_in_decompressed']
                assert path.read_bytes()==blob[start:start+actual['bytes']], path
                embedded += 1
    assert manifests['package_v1']['result']=='PARTIAL_EXPORT'
    assert manifests['package_v2']['result']==manifests['shader_v1']['result']=='PASS_STATIC_EXPORT'
    assert len(manifests['package_v2']['plants'])==13
    assert len(manifests['package_v2']['kernels'])==8
    assert len(manifests['shader_v1']['programs'])==24
    # Check new topic links; existing historical documents have unrelated missing artifacts.
    topic=ROOT/'docs/competitor/水草与岸草功能分析.md'
    links=[]
    for target in re.findall(r'\]\(([^)]+)\)',topic.read_text(encoding='utf8')):
        if '://' in target or target.startswith('#'):
            continue
        path=(topic.parent/target.split('#')[0]).resolve()
        if path!=OUT:
            assert path.is_file(), path
        links.append(str(path))
    claims={
        'VEG-TYPES-01': ['package_v2/manifest.json','package_v2/objects/level0_480.raw','package_v2/objects/level0_496.raw'],
        'VEG-DISTRIBUTION-01': ['package_v2/compute/Distribution_0_0.asm'],
        'VEG-MOTION-01': ['package_v2/compute/Update_0_0.asm'],
        'VEG-TERRAIN-01': ['package_v2/compute/Update_0_0.asm'],
        'VEG-EDIT-01': ['package_v2/compute/Spawn_0_0.asm','package_v2/compute/Kill_0_0.asm','package_v2/compute/Paint_0_0.asm','shader_v1/Forward_progVertex_0.asm'],
        'VEG-RENDER-01': ['package_v2/objects/sharedassets0.assets_580.json','shader_v1/Forward_progFragment_0.asm'],
    }
    report=dict(date='2026-10-21',scope='Package-only vegetation visual configuration and compiled instructions; no RDC/live/business analysis',
        result='PASS_SOURCE_RANGES_AND_ARTIFACT_IDENTITIES', sources=sources,
        source_unchanged_from_export=True,
        tools=[identity(ROOT/'docs/competitor/tools'/n) for n in ('analyze_vegetation.py','extract_vegetation_shader.py','verify_vegetation_evidence.py')],
        manifests={n:identity(BASE/n/'manifest.json') for n in names},
        preserved_failure=dict(identity(BASE/'package_v1/analyze_vegetation.py'),errors=manifests['package_v1']['errors']),
        verification=dict(indexed_artifacts=artifacts,source_ranges=ranges,decompressed_bytecode_ranges=embedded,topic_links=len(links),
                          limitation='Static byte identity and link checks only; no GPU execution or dynamic behavior validation'),
        claims={k:[identity(BASE/p) for p in paths] for k,paths in claims.items()},
        derived_assets='Source textures and proxy meshes for research; not installed as production game resources',
        files=[identity(p) for p in sorted(BASE.rglob('*')) if p.is_file()])
    OUT.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps(dict(result=report['result'],**report['verification'])))


if __name__=='__main__':
    main()
