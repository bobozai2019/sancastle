"""Group the existing ordered descriptors, with explicit dispatch dependencies."""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import shutil

ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--base',type=Path,required=True)
p.add_argument('--name',default='t06_lists_v1')
args=p.parse_args()
base=args.base.resolve()
target=ROOT/'test_output/muscl_performance_round2/projects'/args.name
evidence=ROOT/'task/muscl_performance_round2/验收'/args.name
shutil.copytree(base,target)
evidence.mkdir(parents=True,exist_ok=False)
relative='scripts/simulation/unified_edit/water_muscl.gd'
path=target/relative
before=path.read_text(encoding='utf-8')
after=before.replace('# retains its original compute-list boundary and dispatch order.',
 '# retains its original dispatch order. Adjacent dispatches share a list with\n# an explicit whole-dispatch dependency; callbacks keep separate lists.')
needle='\tfor stage: RecordingPass in _recording:\n\t\tif sampled:'
assert after.count(needle)==1
after=after.replace(needle,'''\t# The list is local to this recording call, never cached across ticks.
\tvar list: int=-1
\tfor stage: RecordingPass in _recording:
\t\tif stage.callback_kind!=0 and list!=-1:
\t\t\trd.compute_list_end();list=-1
\t\tif sampled:''')
needle='\t\tvar list:=rd.compute_list_begin()'
assert after.count(needle)==1
after=after.replace(needle,'\t\tif list==-1:list=rd.compute_list_begin()')
needle='\t\trd.compute_list_end()\n\tif sampled:diagnostic.pass_begin("finish",-1,-1)'
assert after.count(needle)==1
after=after.replace(needle,'''\t\t# Covers image/storage writes and GPU-generated indirect arguments before
\t\t# any following dispatch, including zero-work indirect branches.
\t\trd.compute_list_add_barrier(list)
\tif list!=-1:rd.compute_list_end()
\tif sampled:diagnostic.pass_begin("finish",-1,-1)''')
path.write_text(after,encoding='utf-8',newline='\n')
snapshot=evidence/'sources'/relative;snapshot.parent.mkdir(parents=True,exist_ok=True)
shutil.copy2(path,snapshot)
(evidence/'candidate.diff').write_text(''.join(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile='a/'+relative,tofile='b/'+relative)),encoding='utf-8')
(evidence/'identity.json').write_text(json.dumps({'base':str(base),'candidate':str(target),'source_hashes':{relative:hashlib.sha256(path.read_bytes()).hexdigest()},'scope':'Same descriptor order and bindings; explicit dispatch barrier; end before callbacks and finish/tail; no new RIDs or persistent list IDs'},indent=2),encoding='utf-8')
print(target)
