"""Freeze final current source/documentation identities and terminal gate links."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
ROOT=Path(__file__).resolve().parents[2]
TASK=ROOT/'task/sandcastle_unified_edit_pipeline'
def identity(p):return {'path':p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);args=parser.parse_args();folder=args.output.resolve();folder.mkdir(parents=True,exist_ok=False)
    gate=json.loads((TASK/'验收/G8_联合门.json').read_text('utf-8'));audit=json.loads((TASK/'验收/G8_文档终核对.json').read_text('utf-8'));assert gate['G8_pass'] and gate['overall_completed']==36 and audit['pass']
    paths=set()
    cost=json.loads((ROOT/'test_output/unified_edit_pipeline/g8_cost_joint02/report.json').read_text('utf-8'));paths.update(cost['current_sources'])
    arch=json.loads((ROOT/'test_output/unified_edit_pipeline/g8_architecture_final01/report.json').read_text('utf-8'));paths.update(arch['sources'])
    docs=json.loads((ROOT/'docs/project-execution-guide.sources.json').read_text('utf-8'));assert not docs['preview_final'];paths.update(docs['sources'])
    paths.update(p.relative_to(ROOT).as_posix() for p in TASK.rglob('*') if p.is_file() and p.suffix in {'.md','.json','.html','.py'})
    paths.update(['docs/project-execution-guide.html','docs/project-execution-guide.sources.json','docs/README.md','tools/unified_edit_pipeline/build_g8_gate.py','tools/unified_edit_pipeline/audit_final_delivery.py','tools/unified_edit_pipeline/seal_final_delivery.py'])
    source_index={name:identity(ROOT/name) for name in sorted(paths)}
    with zipfile.ZipFile(folder/'sources.zip','x',zipfile.ZIP_DEFLATED) as z:
        for name in sorted(paths):z.write(ROOT/name,name)
        z.writestr('source-index.json',json.dumps(source_index,indent=2))
    with zipfile.ZipFile(folder/'sources.zip') as z:
        assert z.testzip() is None and len(z.namelist())==len(set(z.namelist()))
        for name,meta in source_index.items():assert hashlib.sha256(z.read(name)).hexdigest()==meta['sha256']
    evidence=[]
    for name in ['G0_基线噪声与比较门.json',*[f'G{i}_联合门.json' for i in range(1,9)],'G8_功能组件.json','G8_长稳组件.json','G8_成本组件.json','G8_HTML终验.json','G8_文档候选核对.json','G8_文档终核对.json']:
        evidence.append(identity(TASK/'验收'/name))
    evidence.append(identity(ROOT/'test_output/unified_edit_pipeline/g8_cost_joint02/seal.json'))
    result={'schema':1,'status':'complete','overall_completed':36,'overall_total':36,'G8_pass':True,'source_archive':identity(folder/'sources.zip'),'source_files':len(paths),'evidence':evidence,'html':identity(ROOT/'docs/project-execution-guide.html'),'source_index':identity(ROOT/'docs/project-execution-guide.sources.json'),'primary_report':'task/sandcastle_unified_edit_pipeline/验收/G8_联合门.md','scope':'Final current source/plan/document bytes and immutable gate links. Raw run artifacts remain in separately indexed original evidence groups; historical failures and user changes are preserved.'}
    target=TASK/'验收/G8_交付索引.json';assert not target.exists();target.write_text(json.dumps(result,ensure_ascii=False,indent=2),'utf-8');print('FINAL_DELIVERY_SEALED',len(paths))
if __name__=='__main__':main()
