"""Archive current source identity and index actual runs without granting Gates."""
import argparse
from datetime import datetime,timezone
import hashlib
import json
from pathlib import Path
import shutil

ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'task/water_foam_visual/验收'

def digest(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stamp',required=True)
    args=parser.parse_args()
    dest=BASE/'source_snapshots'/args.stamp
    dest.mkdir(parents=True,exist_ok=False);(dest/'.gdignore').touch()
    paths=[
        'assets/water_material_natural_candidate/async_rdc_water.gdshader',
        'assets/water_foam/foam_detail.png','assets/water_foam/foam_detail.png.import',
        'assets/water_foam/README.md','assets/water_foam/organic_generation.json',
        'assets/water_sides/water_sides.gdshader','assets/water_sides/geometry_manifest.json',
        'assets/parameters/catalog.json','scripts/parameters/parameter_service.gd',
        'tools/parameter_windows/build_windows.py','scenes/parameters/parameter_windows.tscn',
        'scripts/simulation/unified_edit/presentation.gd','project.godot',
        'tests/integration/export_startup_probe.gd','tools/validate_export.py',
        'docs/当前项目技术方案.md','docs/当前技术规格.md','docs/参数窗口.md',
        'tools/docs/technical_panorama_content.py','tools/docs/build_unified_execution_guide.py',
        'docs/technical-panorama.sources.json','docs/project-execution-guide.sources.json',
    ]
    for scene in ['main','test1_geometry']:
        paths.extend([f'scenes/unified_edit/presentation/{scene}.tscn',f'assets/unified_edit/presentation/{scene}.json'])
    paths.extend(p.relative_to(ROOT).as_posix() for p in (ROOT/'tests/visual_water_alignment').glob('foam_*.gd'))
    paths.extend(p.relative_to(ROOT).as_posix() for p in (ROOT/'tools/water_foam').iterdir() if p.suffix in ['.gd','.py'])
    sources=[]
    for relative in sorted(set(paths)):
        source=ROOT/relative
        if not source.is_file():raise SystemExit('Missing source '+relative)
        target=dest/relative;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
        sources.append({'path':relative,'bytes':source.stat().st_size,'sha256':digest(target)})
    identity={'created_utc':datetime.now(timezone.utc).isoformat(),'scope':'Current source snapshot. Historical run identity comes from each run, never inferred from this snapshot.','sources':sources}
    (dest/'identity.json').write_text(json.dumps(identity,ensure_ascii=False,indent=2),encoding='utf-8')
    runs=[]
    for gate in ['G0','G1','G2','G3','G4','G5']:
        for result_path in sorted((BASE/gate).glob('*/*/result.json')):
            folder=result_path.parent
            row={'run':folder.relative_to(BASE).as_posix(),'process':json.loads(result_path.read_text('utf-8'))}
            probe=folder/'probe.json'
            if probe.exists():
                data=json.loads(probe.read_text('utf-8-sig'))
                row['probe_pass']=data.get('pass');row['checks']=len(data.get('checks',[]))
                row['failed_checks']=[x.get('name') for x in data.get('checks',[]) if not x.get('pass')]
            row['artifacts']=[{'path':p.name,'bytes':p.stat().st_size,'sha256':digest(p)} for p in sorted(folder.iterdir()) if p.is_file() and p.suffix in ['.json','.png','.mp4','.csv','.log','.txt','.sandue']]
            runs.append(row)
    # Export validation has a deeper layout and report.json receipts rather
    # than scene/result.json. Preserve these separately from runtime probes.
    for receipt_path in sorted((BASE/'G4').glob('*/isolated/report.json')):
        receipt=json.loads(receipt_path.read_text('utf-8'))
        export_dir=receipt_path.parent.parent
        row={'run':receipt_path.parent.relative_to(BASE).as_posix(),
             'kind':'outside_project_pck',
             'pass':receipt.get('pass'),
             'pack_sha256':receipt.get('pack_sha256'),
             'probe_sha256':receipt.get('probe_sha256'),
             'scene_runs':receipt.get('runs',[])}
        row['artifacts']=[{'path':p.relative_to(export_dir).as_posix(),
                           'bytes':p.stat().st_size,'sha256':digest(p)}
                          for p in sorted(export_dir.rglob('*'))
                          if p.is_file() and p.suffix in ['.json','.png','.log','.txt']]
        pack=export_dir/'sandcastle.pck'
        if pack.is_file():
            row['retained_pack_sha256']=digest(pack)
            row['retained_pack_matches_receipt']=row['retained_pack_sha256']==row['pack_sha256']
        runs.append(row)
    summaries=[]
    for gate in ['G0','G1','G2','G3','G4','G5']:
        for folder in sorted((BASE/gate).iterdir()):
            if not folder.is_dir():continue
            for p in sorted(folder.iterdir()):
                if p.is_file() and p.suffix in ['.json','.md','.csv','.log','.txt']:
                    summaries.append({'path':p.relative_to(BASE).as_posix(),'bytes':p.stat().st_size,'sha256':digest(p)})
    gate_files=list(BASE.glob('*.md'))+list((BASE/'G5').glob('*.json'))
    summaries.extend({'path':p.relative_to(BASE).as_posix(),'bytes':p.stat().st_size,'sha256':digest(p)} for p in sorted(gate_files))
    (dest/'run_inventory.json').write_text(json.dumps({'scope':'Raw execution outcomes, not aggregate Gate acceptance','runs':runs,'summary_artifacts':summaries},ensure_ascii=False,indent=2),encoding='utf-8')
    index_path=BASE/'index.json'
    index=json.loads(index_path.read_text('utf-8'))
    index['updated_at']=identity['created_utc']
    index['final_source_snapshot']=str((dest/'identity.json').relative_to(BASE).as_posix())
    index['execution_inventory']=str((dest/'run_inventory.json').relative_to(BASE).as_posix())
    index_path.write_text(json.dumps(index,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'Archived {len(sources)} source files; indexed {len(runs)} actual runs. Gate statuses unchanged.')

if __name__=='__main__':main()
