"""Audit saved diagnostic curves against a plain solver run; no simulation writes."""
import argparse, csv, hashlib, json
from pathlib import Path
import numpy as np

p = argparse.ArgumentParser()
p.add_argument('observed', type=Path)
p.add_argument('plain', type=Path)
a = p.parse_args()
data = json.loads((a.observed / 'velocity_curve_probe.json').read_text(encoding='utf-8-sig'))
fields = ['rock', 'sand', 'water', 'momentum_x', 'momentum_z', 'sediment',
          'wetness', 'compaction', 'obstacle', 'flux', 'published_sand', 'published_water']
equal = []
loss = []
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
for row in data['rows']:
    for field in fields:
        name = row['prefix'] + '_' + field + '.bin'
        x, y = sha(a.observed / name), sha(a.plain / name)
        equal.append(dict(name=name, observed_sha256=x, plain_sha256=y, equal=x == y))
    raw = (a.observed / (row['prefix'] + '_step_loss.bin')).read_bytes()
    f = np.frombuffer(raw, dtype='<f4').reshape(-1, 8)
    u = np.frombuffer(raw, dtype='<u4').reshape(-1, 8)
    flags = int(np.bitwise_or.reduce(u[:, 7] >> 24))
    events = [int(u[:, k].astype(np.uint64).sum()) for k in range(4, 7)]
    events.append(int((u[:, 7] & 0xffffff).astype(np.uint64).sum()))
    loss.append(dict(grid=row['grid'], speed_m_s=row['signed_speed_m_s'], tick=row['completed_tick'],
                     absolute_loss_m4_s=float(f[:, 3].astype(float).sum() * .015625),
                     energy_defined_m5_s2=float(f[:, 2].astype(float).sum() * .015625),
                     state_flags=flags, events=events))
result = dict(diagnostic_run=str(a.observed.resolve()), plain_run=str(a.plain.resolve()),
              pass_all=data['pass'] and all(x['equal'] for x in equal) and all(x['state_flags'] == 0 for x in loss),
              count=len(equal), files=equal)
(a.observed / 'observation_equivalence.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
(a.observed / 'loss_summary.json').write_text(json.dumps(dict(scope='Cumulative actual substep observations; net momentum may cancel; undefined energy separate', rows=loss), indent=2), encoding='utf-8')
with (a.observed / 'velocity_curve_metrics.csv').open('w', newline='', encoding='utf-8') as out:
    keys = ['grid', 'signed_speed_m_s', 'completed_tick', 'actual_sim_s', 'water_m3',
            'roi_migration_m3', 'eta_peak_wet_m', 'max_speed_m_s', 'water_relative_error', 'max_substeps']
    w = csv.DictWriter(out, fieldnames=keys); w.writeheader()
    for row in data['rows']: w.writerow({k: row[k] for k in keys})
names = ['observation_equivalence.json', 'loss_summary.json', 'velocity_curve_metrics.csv']
index = dict(tool=str(Path(__file__).resolve()), tool_sha256=sha(Path(__file__)),
             arguments=[str(a.observed), str(a.plain)],
             files=[dict(name=n, size=(a.observed/n).stat().st_size, sha256=sha(a.observed/n)) for n in names])
(a.observed / 'post_analysis_index.json').write_text(json.dumps(index, indent=2), encoding='utf-8')
print(json.dumps(dict(pass_all=result['pass_all'], count=len(equal), samples=len(loss))))
raise SystemExit(0 if result['pass_all'] else 1)
