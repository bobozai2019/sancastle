"""Read-only Ground compute export; no managed methods or business analysis."""
import hashlib, json, sys, platform
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tests/investigation/brush_hit_competitor/deps'))
import UnityPy
from analyze_transport import disassemble
def sha(b): return hashlib.sha256(b).hexdigest()
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=False)
source = ROOT / 'sandcastlegame/Sandcastle_Data/sharedassets0.assets'
before = sha(source.read_bytes())
env = UnityPy.load(str(source))
index = []
for obj in env.objects:
    if obj.type.name != 'ComputeShader' or obj.path_id != 640: continue
    tree = obj.read_typetree()
    raw = obj.get_raw_data()
    (out/'Ground.raw').write_bytes(raw)
    (out/'Ground.tree.json').write_text(json.dumps(tree,ensure_ascii=False,indent=2),encoding='utf-8')
    for vi,v in enumerate(tree['variants']):
        if v['targetRenderer'] != 2: continue
        for ki,k in enumerate(v['kernels']):
            for ui,u in enumerate(k['uniqueVariants']):
                code = bytes(u['code'])
                stem = k['name']+'_'+str(ui)
                asm = disassemble(code)
                (out/(stem+'.dxbc')).write_bytes(code)
                (out/(stem+'.txt')).write_text(asm,encoding='utf-8')
                offset = raw.find(code)
                assert offset >= 0
                index.append(dict(name=stem,selector=f'variants[{vi}].kernels[{ki}].uniqueVariants[{ui}]',
                    object_offset=offset,source_offset=obj.byte_start+offset,size=len(code),sha256=sha(code),
                    disassembly_sha256=sha(asm.encode()),bindings={x:u[x] for x in ['cbs','inBuffers','outBuffers','textures']},
                    constant_buffers=[v['constantBuffers'][i] for i in u['cbVariantIndices']]))
    manifest=dict(source=str(source),source_size=source.stat().st_size,source_sha256=before,
        unchanged=before==sha(source.read_bytes()),path_id=obj.path_id,byte_start=obj.byte_start,byte_size=obj.byte_size,
        object_sha256=sha(raw),unity=str(obj.assets_file.unity_version),unitypy=UnityPy.__version__,python=platform.python_version(),
        script=str(Path(__file__).resolve()),script_sha256=sha(Path(__file__).read_bytes()),command='python '+str(Path(__file__).resolve())+' '+str(out),
        disassembler='C:/Windows/System32/d3dcompiler_47.dll',disassembler_sha256=sha(Path('C:/Windows/System32/d3dcompiler_47.dll').read_bytes()),
        scope='Ground compute object only; no external payload dependency; bytecode and derived disassembly, not original HLSL',index=index)
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print(json.dumps([x['name'] for x in index]))
