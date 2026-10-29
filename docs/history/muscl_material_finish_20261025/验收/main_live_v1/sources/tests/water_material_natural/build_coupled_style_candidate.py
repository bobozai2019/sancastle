"""Prepare an isolated coupled candidate while retaining the existing sand worker body."""
import hashlib, json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
worker = root/'scripts/visual/test1_beach_edit_worker_entry.gd'
body = worker.read_text(encoding='utf-8').split('\n',1)[1]
candidate = root/'assets/water_material_natural_candidate/style_worker_entry.gd'
candidate.write_text('extends "res://assets/water_material_natural_candidate/style_entry.gd"\n'+body,encoding='utf-8')
assert candidate.read_text(encoding='utf-8').split('\n',1)[1] == body
fixed = root/'scenes/water_material_natural_candidate/style_combination.tscn'
coupled = root/'scenes/water_material_natural_candidate/style_coupled_candidate.tscn'
coupled.write_text(fixed.read_text(encoding='utf-8').replace('scenes/water_material_natural_candidate/rdc_v1_fixed.tscn','scenes/water_material_natural_candidate/rdc_v1_coupled.tscn').replace('/style_entry.gd','/style_worker_entry.gd'),encoding='utf-8')
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
manifest = {'source_worker':str(worker),'source_worker_sha256':sha(worker),
    'candidate_worker':str(candidate),'candidate_worker_sha256':sha(candidate),
    'unchanged_worker_body_sha256':hashlib.sha256(body.encode()).hexdigest(),
    'source_fixed_candidate':str(fixed),'source_fixed_candidate_sha256':sha(fixed),
    'coupled_candidate':str(coupled),'coupled_candidate_sha256':sha(coupled),
    'command':'python tests/water_material_natural/build_coupled_style_candidate.py',
    'scope':'Only extends parent and packed-scene base change; existing worker body preserved exactly. Prepared for post-G3 integration checks, no formal files changed and no validation claimed.'}
(candidate.parent/'style_worker_generation.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print(json.dumps(manifest))
