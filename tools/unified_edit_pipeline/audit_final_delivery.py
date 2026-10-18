"""Verify actual final documentation/source bytes and goal evidence links."""
import argparse
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[2]
TASK=ROOT/'task/sandcastle_unified_edit_pipeline'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
class Links(HTMLParser):
    def __init__(self):super().__init__();self.hrefs=[]
    def handle_starttag(self,tag,attrs):
        if tag=='a':self.hrefs.extend(value for key,value in attrs if key=='href')
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);parser.add_argument('--final',action='store_true');args=parser.parse_args();assert not args.output.exists(),'Fresh audit required';checks=[]
    def check(name,value):checks.append({'name':name,'pass':bool(value)})
    guide=ROOT/'docs/project-execution-guide.html';index=ROOT/'docs/project-execution-guide.sources.json';data=json.loads(index.read_text('utf-8'))
    check('completion_html_status',data['status']=='36/36 · G8已通过；本轮交付见最终联合门。')
    check('correct_preview_or_final_role',data['preview_final']==(not args.final))
    for name,digest in data['sources'].items():check('document_source:'+name,sha(ROOT/name)==digest)
    check('seventeen_actual_code_anchors',len(data['anchors'])==17)
    for anchor in data['anchors']:
        path=ROOT/anchor['path'];lines=path.read_text('utf-8-sig').splitlines()
        check('anchor:'+anchor['path']+'::'+anchor['symbol'],sha(path)==anchor['sha256'] and bool(re.match(r'^(?:static )?func '+re.escape(anchor['symbol'])+r'\(',lines[anchor['line']-1])))
    links=Links();links.feed(guide.read_text('utf-8'))
    for href in links.hrefs:
        check('local_link:'+href,not re.match(r'\w+://',href) and (guide.parent/href.split('#')[0]).resolve().is_file())
    for name in ['G8_功能组件.json','G8_长稳组件.json','G8_成本组件.json']:
        component=json.loads((TASK/'验收'/name).read_text('utf-8'));check('actual_component:'+name,component['status']=='component_pass')
    cost=json.loads((TASK/'验收/G8_成本组件.json').read_text('utf-8'));check('independent_cost_pass',cost['performance_pass'])
    arch=json.loads((ROOT/'test_output/unified_edit_pipeline/g8_architecture_final01/report.json').read_text('utf-8'));check('current_architecture_and_mutants',arch['pass'] and len(arch['negatives'])==9 and all(x['pass'] for x in arch['negatives']))
    frozen=json.loads((ROOT/'test_output/unified_edit_pipeline/g8_formal_frozen01/frozen.json').read_text('utf-8'))['sources']
    for name,digest in frozen.items():check('frozen_runtime_source:'+name,sha(ROOT/name)==digest)
    if args.final:
        gate=json.loads((TASK/'验收/G8_联合门.json').read_text('utf-8'));check('gate_all_thirty_six',gate['G8_pass'] and gate['overall_completed']==gate['overall_total']==36)
        state=(TASK/'执行状态.md').read_text('utf-8')
        completed=set(re.findall(r'^\| (T\d{2}\.\d) \|[^\n]*\| \[已完成\] \|',state,re.M));expected={f'T{i:02d}.{j}' for i in range(9) for j in range(1,5)}
        check('all_thirty_six_state_rows_completed',completed==expected)
        visual=json.loads((TASK/'验收/G8_HTML终验.json').read_text('utf-8'));check('same_visually_inspected_html_bytes',visual['pass'] and visual['html_sha256']==sha(guide))
    result={'pass':all(c['pass'] for c in checks),'checks':checks,'html_sha256':sha(guide),'source_index_sha256':sha(index),'auditor_sha256':sha(Path(__file__)),'final':args.final,'scope':'Source/anchor/link and actual completed-component consistency for final HTML/delivery. Browser visual/interactive QA is separate; this does not invent runtime or performance evidence.'}
    args.output.write_text(json.dumps(result,indent=2),'utf-8');print('DELIVERY_AUDIT',result['pass'],'checks',len(checks));print('FAILURES',[c['name'] for c in checks if not c['pass']]);raise SystemExit(0 if result['pass'] else 1)
if __name__=='__main__':main()
