import json
import sys
from pathlib import Path
import numpy as np

root = Path(sys.argv[1])
labels = sorted(p.name.split('_')[0] for p in root.glob('t*_water.bin'))
fields = {label: {f: np.fromfile(root / f'{label}_{f}.bin', dtype='<f2' if f == 'wetness' else '<f4').astype(float) for f in ['sand', 'water', 'wetness']} for label in labels}
initial = fields[labels[0]]
land = (initial['water'] <= .001) & (initial['sand'] > .16)
ever = np.zeros(65536, dtype=bool)
rows = []
for label in labels:
    d = fields[label]
    ever |= land & (d['water'] > .001)
    exposed = ever & (d['water'] <= .001)
    wet = land & (d['water'] > .001)
    def stats(mask):
        return {'count': int(mask.sum()), 'water_p50_p95_max_m': np.quantile(d['water'][mask], [.5,.95,1]).tolist(), 'wetness_p05_p50_p95_max': np.quantile(d['wetness'][mask], [.05,.5,.95,1]).tolist(), 'wet_delta_p50_max': np.quantile((d['wetness']-initial['wetness'])[mask], [.5,1]).tolist()} if mask.any() else {'count':0}
    row = {'label':label, 'initial_land':stats(land), 'currently_flooded_land':stats(wet), 'previously_flooded_exposed':stats(exposed), 'wetness_all_max':float(d['wetness'].max()), 'wetness_changed_cells':int((d['wetness']!=initial['wetness']).sum())}
    rows.append(row)
print(json.dumps(rows, indent=2))
(root / 'analysis.json').write_text(json.dumps(rows, indent=2), encoding='utf-8')
if 't24' in fields:
    previously_flooded = land & np.logical_or.reduce([fields[t]['water'] > .001 for t in ['t03', 't06', 't10']])
    cohort = previously_flooded & (fields['t16']['water'] <= .001) & (fields['t24']['water'] <= .001)
    result = {'definition': 'Initially exposed thick sand; observed flooded at t03/t06/t10; exposed at both t16 and t24. Intermediate rewetting is not excluded.', 'cells': int(cohort.sum()), 'wetness_t16_median': float(np.median(fields['t16']['wetness'][cohort])), 'wetness_t24_median': float(np.median(fields['t24']['wetness'][cohort]))}
    (root / 'cohort.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
