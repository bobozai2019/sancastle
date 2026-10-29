"""Add the current static water sides to an isolated G0 cost reference only."""
import argparse
import hashlib
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
FILES=['tools/unified_edit_pipeline/reference_cost_probe.gd','scenes/components/water_boundary_sides.tscn','scripts/visual/water_boundary_sides.gd','assets/water_sides/main_boundary.res','assets/water_sides/water_sides.gdshader','assets/water_sides/geometry_manifest.json']
def sha(raw):return hashlib.sha256(raw).hexdigest()
def main():
    p=argparse.ArgumentParser();p.add_argument('--reference',type=Path,required=True);args=p.parse_args();reference=args.reference.resolve()
    assert not reference.is_relative_to(ROOT),'Do not modify the product project'
    index=reference/'reference-index.json';raw=index.read_bytes();data=json.loads(raw)
    assert data['archive_sha256']=='c80d051495eafd39fe7b69d6e4b0ed22f62a474b7658593bb0fc38cf8ff1939a'
    if data.get('render_overlay'):
        assert data['render_overlay']['files']==FILES
        for name in FILES:assert sha((reference/name).read_bytes())==data['files'][name]['sha256']==sha((ROOT/name).read_bytes())
        print('REFERENCE_OVERLAY_ALREADY_IDENTICAL');return
    before=reference/'reference-index.before-render-overlay.json';assert not before.exists();before.write_bytes(raw)
    for name in FILES:
        target=(reference/name).resolve();assert target.is_relative_to(reference)
        payload=(ROOT/name).read_bytes();assert not target.exists() or target.read_bytes()==payload,'Never overwrite a different reference source'
        target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(payload)
        data['files'][name]={'sha256':sha(payload),'bytes':len(payload),'origin':'g8_reference_only_same_current_water_sides_render_overlay'}
    data['render_overlay']={'reason':'Reference-only same current static WaterSides rendering load. Original G0 source/archive and authority/scheduler/observer code remain unchanged.','files':FILES,'before_index_sha256':sha(raw)}
    index.write_text(json.dumps(data,indent=2),'utf-8');print('REFERENCE_OVERLAY_APPLIED',len(FILES))
if __name__=='__main__':main()
