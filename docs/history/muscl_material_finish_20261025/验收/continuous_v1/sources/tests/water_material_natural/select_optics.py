"""Freeze the reviewed T03 single-factor choice without rewriting source profiles."""
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[2];a=ROOT/'assets/water_material_natural_candidate';s=ROOT/'scenes/water_material_natural_candidate'
p=json.loads((a/'optics_unrefracted.json').read_text());p['extinction_deep_m']=0.40
(a/'optics_selected.json').write_text(json.dumps(p,indent=2),encoding='utf-8')
(s/'optics_selected.tscn').write_text((s/'optics_unrefracted.tscn').read_text().replace('optics_unrefracted.json','optics_selected.json'),encoding='utf-8')
(s/'optics_depth_selected.tscn').write_text((s/'optics_depth_fixture.tscn').read_text().replace('optics_reconstructed.json','optics_selected.json'),encoding='utf-8')
# Separate versioned refusal results; preserve schema1's original version-2 rejection.
test=(ROOT/'tests/water_material_natural/reject_optics_profiles.gd').read_text().replace('t03_profile_rejections"','t03_profile_rejections_v2"').replace('optics_reconstructed.json','optics_selected.json').replace('p.optics_schema_version = 2','p.optics_schema_version = 99')
test=test.replace('"unset_extinction"]','"unset_extinction","schema1_new_mode"]').replace('"unset_extinction": p.extinction_deep_m = null','"unset_extinction": p.extinction_deep_m = null\n\t\t\t"schema1_new_mode": p.optics_schema_version = 1')
test=test.replace('ten malformed optics profiles','eleven malformed optics profiles')
(ROOT/'tests/water_material_natural/reject_optics_profiles_v2.gd').write_text(test,encoding='utf-8')
