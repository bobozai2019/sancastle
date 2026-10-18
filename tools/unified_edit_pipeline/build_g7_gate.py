"""Evidence-only G7 gate; never rewrites historical component outcomes."""
import hashlib
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
TASK=ROOT/'task/sandcastle_unified_edit_pipeline'
def identity(path):
    p=ROOT/path;return {'path':path,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
def main():
    groups=['g7_extensions_final01','g7_features_snapshot02','g7_extension_runtime02','g7_architecture_final03']
    evidence=[];runs=0;gpu=0;independent=0
    for group in groups:
        folder=ROOT/'test_output/unified_edit_pipeline'/group
        report=json.loads((folder/'report.json').read_text('utf-8'));assert report['pass']
        if 'runs' in report:
            audit=json.loads((folder/'audit.json').read_text('utf-8'));assert audit['pass'];independent+=len(audit['checks']);runs+=len(report['runs'])
            for row in report['runs']:
                d=json.loads(Path(row['evidence']).read_text('utf-8'));assert d['pass'];gpu+=len(d['checks'])
        else:independent+=len(report['checks'])
        for name in ['report.json','audit.json','sources.zip','verification_sources.zip','artifact-index.json']:
            p=folder/name
            if p.exists():evidence.append(identity(p.relative_to(ROOT).as_posix()))
    fixture=json.loads((ROOT/'assets/unified_edit/extensions/fixture_identity.json').read_text('utf-8'))
    assert len(fixture['core_before'])==51
    for path,digest in fixture['core_before'].items():assert identity(path)['sha256']==digest
    result={'schema':1,'status':'pass','date':'2026-10-18','G7_pass':True,'overall_completed':32,'overall_total':36,'T07_completed':4,'completed_subgoals':['T07.1','T07.2','T07.3','T07.4'],'gpu_runs':runs,'gpu_checks':gpu,'independent_checks':independent,'core_unchanged_count':51,'evidence':evidence,'architecture':{'resource_reference_files':606,'reference_edges':3503,'sensitive_methods':147,'sealed_code_resource_boundaries':561,'adversarial_samples':9,'limitations':'Conservative reference closure and sealed reviewed boundaries, not arbitrary-program call-graph proof. Four missing dormant test/evidence references explicitly classified; debugger autoload development boundary is explicit.'},'guide':identity('docs/unified-edit-extension-guide.md'),'policy':identity('tools/unified_edit_pipeline/architecture_policy.json'),'preserved_failures':['g7_features01: one configuration digest differs, other observed source/selected-profile identities equal; no full snapshot captured, cause unknown. Final snapshot02 has all sixteen full JSON/canonical Variant snapshots equal.','g7_extension_runtime01: live unchanged chunks need not carry newest version and restore preserves command highwater; probe assumptions fixed, original bytes/logs/126-source archive retained.','g7_architecture_final02: duplicate identical project.godot ZIP member; final03 ZIP unique member check added, old archive retained.'],'remaining':['T08.1 final frozen entry/function/fault regression','T08.2 ten lifecycle rounds and three minutes actual mixed interaction','T08.3 visible paired phase/frame cost comparison and independent judgment','T08.4 final docs/HTML/unique-path proof and 36-goal delivery']}
    p=TASK/'验收/G7_联合门.json';assert not p.exists();p.write_text(json.dumps(result,ensure_ascii=False,indent=2),'utf-8');print('G7_PASS',runs,gpu,independent)
if __name__=='__main__':main()
