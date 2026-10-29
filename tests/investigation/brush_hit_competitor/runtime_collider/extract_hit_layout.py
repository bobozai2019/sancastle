"""Bounded same-version RaycastHit layout; preserve source bytes and selectors."""
import runpy,contextlib,io,os,json,hashlib,argparse
from pathlib import Path
HERE=Path(__file__).resolve().parent
def main():
    p=argparse.ArgumentParser();p.add_argument('--out',required=True);a=p.parse_args();out=Path(a.out).resolve();out.mkdir(exist_ok=False,parents=True)
    os.environ['BRUSH_HIT_OUTPUT']=str(out/'decoder_baseline')
    with contextlib.redirect_stdout(io.StringIO()):n=runpy.run_path(str(HERE.parent/'metadata_fields.py'))
    mb,bb=n['mb'],n['bb'];t=next(t for t in n['types'] if t['name']=='RaycastHit' and t['namespace']=='UnityEngine');raw=[]
    def keep(name,b,source,offset):
        f=out/name;f.write_bytes(b);raw.append({'path':str(f),'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest(),'source':str(source),'offset':str(offset),'source_sha256':hashlib.sha256(mb if source==n['META'] else bb).hexdigest()})
    keep('type.raw',mb[t['offset']:t['offset']+76],n['META'],t['offset']);fo=n['off'](n['u64'](bb,n['reg']['field_list_offset']+8*t['index']));fields=[]
    for j in range(t['field_count']):
        idx=t['first_field']+j;o=n['sections']['fields']['offset']+10*idx
        fields.append({'name':n['string'](n['i32'](mb,o)),'native_instance_offset':n['i32'](bb,fo+4*j),'type':n['describe'](n['u16'](mb,o+4))})
        keep('field_'+str(idx)+'.raw',mb[o:o+10],n['META'],o)
    keep('field_offsets.raw',bb[fo:fo+4*t['field_count']],n['BIN'],fo)
    (out/'layout.json').write_text(json.dumps({'type':t,'fields':fields,'raw_index':raw,'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()},indent=2),encoding='utf8')
    print(json.dumps([(f['name'],f['native_instance_offset']) for f in fields]))
if __name__=='__main__':main()
