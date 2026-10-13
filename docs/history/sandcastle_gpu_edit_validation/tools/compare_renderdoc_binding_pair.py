"""Compare ordered dispatch signatures of the successful owned capture pair."""
import hashlib
import json
from pathlib import Path

base=Path('D:/godot/project/sandcastle/task/sandcastle_gpu_edit_validation/evidence')
left=base/'20261011_091015_renderdoc'
right=base/'20261011_092640_renderdoc'
a_name=json.loads((left/'binding_probe_latest.json').read_text())['report']
b_name=json.loads((right/'binding_probe_latest.json').read_text())['report']
a=json.loads((left/a_name).read_text())
b=json.loads((right/b_name).read_text())
assert a['pass'] and b['pass']
rows=[]
for i,(x,y) in enumerate(zip(a['rows'],b['rows'])):
    signature=(x.get('readwrite'),x.get('readonly'),x['dimensions'])==(y.get('readwrite'),y.get('readonly'),y['dimensions'])
    constants=[c.get('buffer_hex') for c in x.get('constants',[])]==[c.get('buffer_hex') for c in y.get('constants',[])]
    def exports(row):
        return {row['readwrite'][v['reflection_index']]:v['export'] for v in row.get('resource_bindings',[]) if 'export' in v}
    xe,ye=exports(x),exports(y)
    fields=[]
    for name in sorted(xe.keys()|ye.keys()):
        xm,ym=xe.get(name),ye.get(name)
        exact=False
        if xm and ym:
            xd=(left/xm['path']).read_bytes();yd=(right/ym['path']).read_bytes()
            assert hashlib.sha256(xd).hexdigest()==xm['sha256']
            assert hashlib.sha256(yd).hexdigest()==ym['sha256']
            exact=xd==yd
        fields.append({'name':name,'byte_equal':exact})
    xs,ys=x['native_shader'],y['native_shader']
    xd=(left/xs['path']).read_bytes();yd=(right/ys['path']).read_bytes()
    assert xd and yd
    assert hashlib.sha256(xd).hexdigest()==xs['sha256'] and hashlib.sha256(yd).hexdigest()==ys['sha256']
    rows.append({'ordinal':i,'writer_event':x['event'],'reader_event':y['event'],'signature_equal':signature,'constant_bytes_equal':constants,'native_shader_equal':xd==yd,'shader_encoding':xs['encoding'],'sand_fields':fields})
ok=len(a['rows'])==len(b['rows']) and all(r['signature_equal'] and r['constant_bytes_equal'] and r['native_shader_equal'] and all(f['byte_equal'] for f in r['sand_fields']) for r in rows)
result={'pass':ok,'writer_report':str(left/a_name),'reader_report':str(right/b_name),'writer_dispatches':len(a['rows']),'reader_dispatches':len(b['rows']),'rows':rows,'scope':'Successful cold continuation pair; ordered reflection/dimensions align this frame. ResourceId/shader identities are capture-local; no precise tick mapping or failed first-divergence claim.'}
result_name='binding_pair_'+a_name.removesuffix('.json')+'_'+b_name
(right/result_name).write_text(json.dumps(result,indent=2),encoding='utf-8')
(right/'binding_pair_latest.json').write_text(json.dumps({'report':result_name}),encoding='utf-8')
print(json.dumps({'pass':ok,'dispatch_pairs':len(rows),'sand_field_pairs':sum(len(r['sand_fields']) for r in rows)}))
assert ok
