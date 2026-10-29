"""Compare fast/slow raw outputs. Only private receipt word27 is a declared new diagnostic."""
import argparse, hashlib, json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('slow',type=Path);p.add_argument('fast',type=Path);a=p.parse_args()
rows=[];ignored=[]
for f in sorted(a.slow.glob('*.bin')):
    if f.name.endswith('_water_receipt.bin') and '_before_' in f.name:
        ignored.append(f.name);continue
    g=a.fast/f.name
    x=f.read_bytes();y=g.read_bytes() if g.exists() else b''
    private=f.name.endswith('_water_receipt.bin')
    cx=x[:108]+x[112:] if private else x
    cy=y[:108]+y[112:] if private else y
    rows.append(dict(name=f.name,equal=cx==cy,private_word27_excluded=private,
                     slow_sha256=hashlib.sha256(x).hexdigest(),fast_sha256=hashlib.sha256(y).hexdigest()))
report=dict(pass_all=bool(rows) and all(r['equal'] for r in rows),count=len(rows),ignored_uninitialized=ignored,
            diagnostic_exception='Private receipt word27 path marker only; all authority and published bytes strict',files=rows)
out=a.fast/'fast_slow_equivalence.json';out.write_text(json.dumps(report,indent=2),encoding='utf-8')
index=dict(tool=str(Path(__file__).resolve()),tool_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
           arguments=[str(a.slow),str(a.fast)],result=out.name,result_sha256=hashlib.sha256(out.read_bytes()).hexdigest())
(a.fast/'post_fast_index.json').write_text(json.dumps(index,indent=2),encoding='utf-8')
print(json.dumps(dict(pass_all=report['pass_all'],count=len(rows),mismatches=[r['name'] for r in rows if not r['equal']])))
raise SystemExit(0 if report['pass_all'] else 1)
