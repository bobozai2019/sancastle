"""Build an isolated read-only retry-path observer; preserve historical tools."""
from pathlib import Path
import hashlib
import json

ROOT=Path(__file__).resolve().parents[2]
TOOLS=ROOT/'tools/muscl_performance'

def main():
    source=(TOOLS/'diagnostic.gd').read_text(encoding='utf-8')
    def change(before,after):
        nonlocal source
        if source.count(before)!=1:raise ValueError('anchor:'+before)
        source=source.replace(before,after)
    change('const SNAPSHOT_BYTES:=2240 # decision 64 + audit 2048 + control 128',
           'const SNAPSHOT_BYTES:=2256 # original 2240 + sampled pre-edge retry cache 16')
    change('var rd: RenderingDevice','var rd: RenderingDevice\nvar retry_cache_source:=RID()')
    change('\t_current.spans.append({"ordinal":_span_serial',
           '\tif label=="edge" and candidate==int(_current.slot) and rk_phase==0:\n'
           '\t\t_current.retry_copy_ok=retry_cache_source.is_valid() and rd.buffer_copy(retry_cache_source,_slots[int(_current.staging_slot)].rid,0,2240,16)==OK\n'
           '\t_current.spans.append({"ordinal":_span_serial')
    change('\t\trow.decision_hex=bytes.slice(0,64).hex_encode();',
           '\t\trow.retry_before_edge_hex=bytes.slice(2240,2256).hex_encode() if row.get("retry_copy_ok",false) else ""\n'
           '\t\trow.decision_hex=bytes.slice(0,64).hex_encode();')
    # Original control bytes stop at 2240; appended data is a separate record.
    change('row.control_hex=bytes.slice(2112).hex_encode()',
           'row.control_hex=bytes.slice(2112,2240).hex_encode()')
    outputs={'tools/muscl_performance/efficiency_diagnostic.gd':source}
    scene=(TOOLS/'diagnostic_scene.gd').read_text(encoding='utf-8')
    scene=scene.replace('res://tools/muscl_performance/diagnostic.gd','res://tools/muscl_performance/efficiency_diagnostic.gd')
    scene=scene.replace('observer=Observer.new()','observer=Observer.new()\n\tobserver.retry_cache_source=p.water.muscl.buffers.retry_cache')
    outputs['tools/muscl_performance/efficiency_diagnostic_scene.gd']=scene
    exact=(TOOLS/'diagnostic_exact.gd').read_text(encoding='utf-8')
    exact=exact.replace('res://tools/muscl_performance/diagnostic.gd','res://tools/muscl_performance/efficiency_diagnostic.gd')
    exact=exact.replace('var observer:=Observer.new()','var observer:=Observer.new()\n\t\tobserver.retry_cache_source=recorder.buffers.retry_cache')
    outputs['tools/muscl_performance/efficiency_diagnostic_exact.gd']=exact
    out=ROOT/'task/muscl_gpu_efficiency/验收/t01_path_tools_v1'
    out.mkdir(parents=True,exist_ok=False)
    identity={}
    for relative,content in outputs.items():
        target=ROOT/relative
        if target.exists():raise FileExistsError(target)
        target.write_text(content,encoding='utf-8',newline='\n')
        archived=out/'sources'/relative;archived.parent.mkdir(parents=True,exist_ok=True)
        archived.write_bytes(target.read_bytes())
        identity[relative]=hashlib.sha256(target.read_bytes()).hexdigest()
    (out/'manifest.json').write_text(json.dumps({'files':identity,'original_observer_sha256':hashlib.sha256((TOOLS/'diagnostic.gd').read_bytes()).hexdigest(),
        'extra_staging_bytes':64,'extra_copies_per_sampled_tick':1,
        'semantics':'Read retry_cache into spare staging suffix immediately before selected-slot phase0 edge. No simulation write or per-stage CPU wait.'},indent=2),encoding='utf-8')
    print(json.dumps(identity))

if __name__=='__main__':main()
