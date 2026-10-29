"""Verify camera-only capture leaves trajectories intact and inspect actual JPEG/AVI frames."""
import argparse, hashlib, json, struct
from pathlib import Path
import numpy as np
from PIL import Image
p=argparse.ArgumentParser(); p.add_argument('b',type=Path); p.add_argument('c',type=Path); p.add_argument('d',type=Path); p.add_argument('e',type=Path); p.add_argument('bc_curve',type=Path); p.add_argument('d_curve',type=Path); p.add_argument('e_curve',type=Path); a=p.parse_args()
fields=['rock','sand','water','momentum_x','momentum_z','sediment','wetness','compaction','obstacle','flux','published_sand','published_water']
records=[]; videos=[]
for letter,run,ref,tag in [('B',a.b,a.bc_curve,'B'),('C',a.c,a.bc_curve,'C'),('D',a.d,a.d_curve,'D_0.5'),('E',a.e,a.e_curve,'E_0.5')]:
    data=json.loads((run/'feedback_probe.json').read_text(encoding='utf-8-sig'))
    assert data['pass'] and len(data['frames'])==151
    avi=(run/f'feedback_{letter}.avi').read_bytes()
    assert avi[:4]==b'RIFF' and avi[8:12]==b'AVI ' and struct.unpack_from('<I',avi,4)[0]==len(avi)-8
    movi=avi.index(b'movi'); idx=avi.index(b'idx1',movi)
    assert struct.unpack_from('<I',avi,idx+4)[0]==151*16
    for n,frame in enumerate(data['frames']):
        jpeg=(run/frame['file']).read_bytes()
        with Image.open(run/frame['file']) as im:
            im.load(); assert im.size==(960,540)
        tag_id,flag,off,size=struct.unpack_from('<4sIII',avi,idx+8+n*16)
        assert tag_id==b'00dc' and flag==16 and size==len(jpeg)
        assert avi[movi+off+8:movi+off+8+size]==jpeg
    videos.append(dict(phase=letter,frames=151,avi_index_checked=True,jpeg_decode_checked=True))
    for row in data['rows']:
        for field in fields:
            name=f"256_{letter}_tick{row['completed_tick']:03d}_{field}.bin"
            refname=f"256_{tag}_tick{row['completed_tick']:03d}_{field}.bin"
            x=hashlib.sha256((run/name).read_bytes()).hexdigest(); y=hashlib.sha256((ref/refname).read_bytes()).hexdigest()
            records.append(dict(name=name,reference=str(ref/refname),equal=x==y,sha256=x,reference_sha256=y))
pixels=[]
for first,second in [('B','D'),('C','E'),('B','C')]:
    for tick in [0,30,150]:
        x=np.asarray(Image.open(getattr(a,first.lower())/f'256_{first}_tick{tick:03d}.png').convert('RGB'))[110:]
        y=np.asarray(Image.open(getattr(a,second.lower())/f'256_{second}_tick{tick:03d}.png').convert('RGB'))[110:]
        pixels.append(dict(pair=first+'/'+second,tick=tick,nonzero_pixels=int(np.any(x!=y,axis=2).sum()),max_channel_difference=int(np.abs(x.astype(int)-y.astype(int)).max()),roi='all image rows>=110 excludes label'))
report=dict(pass_all=all(r['equal'] for r in records),count=len(records),videos=videos,pixel_comparison=pixels,fields=records,
            camera_scene='res://tests/edit_validation/edit_feedback_lab.tscn',comparison='fixed960x540, samecamera/material, diagnostic lab; no competitor fidelity claim')
out=a.e/'feedback_comparison.json'; out.write_text(json.dumps(report,indent=2),encoding='utf-8')
index=dict(tool=str(Path(__file__).resolve()),tool_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),arguments=[str(v) for v in vars(a).values()],file=out.name,sha256=hashlib.sha256(out.read_bytes()).hexdigest())
(a.e/'post_visual_index.json').write_text(json.dumps(index,indent=2),encoding='utf-8')
print(json.dumps(dict(pass_all=report['pass_all'],count=len(records),pixels=pixels)))
raise SystemExit(0 if report['pass_all'] else 1)
