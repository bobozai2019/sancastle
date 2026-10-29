"""Export the packed-state to CPU-cell mapping; no CPU methods decoded."""
import argparse
import hashlib
import json
import sys
from pathlib import Path

from analyze_transport import disassemble

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tests/investigation/brush_hit_competitor/deps'))
import UnityPy


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--out', required=True)
    a = p.parse_args()
    out = Path(a.out).resolve()
    out.mkdir(exist_ok=False, parents=True)
    source = ROOT / 'sandcastlegame/Sandcastle_Data/sharedassets0.assets'
    before = hashlib.sha256(source.read_bytes()).hexdigest()
    assert before == '6dd7bb6bc7d926fd43c08d22c9c767b7edf531cf11a4a555fcd41830f2f9c721'
    env = UnityPy.load(str(source))
    obj = next(o for o in env.objects if o.path_id == 646 and o.assets_file.name == source.name)
    raw = obj.get_raw_data()
    tree = obj.read_typetree()
    assert tree['m_Name'] == 'Readback'
    (out / 'object.raw').write_bytes(raw)
    (out / 'object.json').write_text(json.dumps(tree, indent=2), encoding='utf-8')
    v = next(v for v in tree['variants'] if v['targetRenderer'] == 2)
    k = next(k for k in v['kernels'] if k['name'] == 'Update')
    u = k['uniqueVariants'][0]
    code = bytes(u['code'])
    (out / 'update.dxbc').write_bytes(code)
    (out / 'update.txt').write_text(disassemble(code), encoding='utf-8')
    positions = []
    pos = raw.find(code)
    while pos >= 0:
        positions.append(pos)
        pos = raw.find(code, pos+1)
    assert positions
    after = hashlib.sha256(source.read_bytes()).hexdigest()
    index = {'source': str(source), 'bytes': source.stat().st_size, 'source_sha256': before,
             'source_after_sha256': after, 'source_unchanged': before == after,
             'path_id': '646', 'byte_start': obj.byte_start, 'object_bytes': len(raw),
             'object_sha256': hashlib.sha256(raw).hexdigest(),
             'code_sha256': hashlib.sha256(code).hexdigest(), 'code_offsets': positions,
             'selector': 'variants[targetRenderer=2].kernels[name=Update].uniqueVariants[0]',
             'bindings': {n: u[n] for n in ['inBuffers', 'outBuffers']},
             'constants': [v['constantBuffers'][i] for i in u['cbVariantIndices']],
             'tool': 'UnityPy '+UnityPy.__version__+' / D3DDisassemble',
             'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
             'command': 'python '+str(Path(__file__).resolve())+' --out '+str(out),
             'scope': 'packed ground/water to ReadbackCell correspondence only; no CPU methods decoded'}
    (out / 'index.json').write_text(json.dumps(index, indent=2), encoding='utf-8')
    print(json.dumps({'source_unchanged': before == after, 'path_id': 646, 'code_bytes': len(code)}))


if __name__ == '__main__':
    main()
