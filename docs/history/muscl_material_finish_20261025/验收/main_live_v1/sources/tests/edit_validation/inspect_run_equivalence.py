"""Hash paired probe raw files; ignore uninitialized private pre-edit diagnostic receipt."""
import argparse, hashlib, json
from pathlib import Path
p=argparse.ArgumentParser(); p.add_argument('full',type=Path); p.add_argument('local',type=Path); a=p.parse_args()
rows=[]; ignored=[]
for f in sorted(a.full.glob('*.bin')):
    if f.name.endswith('water_receipt.bin') and '_before_' in f.name:
        ignored.append(f.name); continue
    g=a.local/f.name
    x=hashlib.sha256(f.read_bytes()).hexdigest(); y=hashlib.sha256(g.read_bytes()).hexdigest() if g.exists() else None
    rows.append(dict(name=f.name,full_sha256=x,local_sha256=y,equal=x==y))
report=dict(pass_all=bool(rows) and all(r['equal'] for r in rows),count=len(rows),ignored=ignored,files=rows)
out=a.local/'full_local_equivalence.json';out.write_text(json.dumps(report,indent=2),encoding='utf-8')
index=dict(tool=str(Path(__file__).resolve()),tool_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),arguments=[str(a.full),str(a.local)],file=out.name,sha256=hashlib.sha256(out.read_bytes()).hexdigest())
(a.local/'post_equivalence_index.json').write_text(json.dumps(index,indent=2),encoding='utf-8')
print(json.dumps(dict(pass_all=report['pass_all'],count=len(rows),ignored=len(ignored),mismatches=[r['name'] for r in rows if not r['equal']])))
raise SystemExit(0 if report['pass_all'] else 1)
