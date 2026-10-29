import json,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];a=ROOT/'assets/water_material_natural_candidate';s=ROOT/'scenes/water_material_natural_candidate'
p=json.loads((a/'foam_shape_baseline.json').read_text())
p['fine'].update(size_mode='weighted',size_range=[.65,2.2],clustering_strength=.35,jitter_m=.05)
p['contact']['shape_mode']='multiscale'
(a/'foam_combination.json').write_text(json.dumps(p,indent=2),encoding='utf-8')
(s/'foam_combination.tscn').write_text((s/'foam_shape_baseline.tscn').read_text().replace('foam_shape_baseline.json','foam_combination.json'),encoding='utf-8')
print(hashlib.sha256((a/'foam_combination.json').read_bytes()).hexdigest())
