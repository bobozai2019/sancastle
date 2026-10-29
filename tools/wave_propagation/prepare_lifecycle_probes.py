"""Create explicit MUSCL variants of existing tests in an isolated runtime.

Select the frozen algorithm, wait for the complete boot precondition, and add
an algorithm assertion on scene switches. Existing assertions stay unchanged.
Every original dependency and exact edit is recorded for review.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re


def main():
    p=argparse.ArgumentParser();p.add_argument('--runtime',type=Path,required=True);p.add_argument('--extend',action='store_true');p.add_argument('--refresh',action='append',default=[]);a=p.parse_args()
    root=Path(__file__).resolve().parents[2];runtime=a.runtime.resolve();dest=runtime/'tools/wave_propagation/g4_generated';dest.mkdir(exist_ok=a.extend)
    selections={'restore':'tests/integration/unified_edit_restore_probe.gd','initialization':'tests/integration/unified_edit_initialization_probe.gd','checkpoint':'tests/integration/unified_edit_checkpoint_probe.gd',
                'formal_final':'tests/integration/unified_edit_formal_final_lifecycle_probe.gd','formal_boundary':'tests/integration/unified_edit_formal_boundary_probe.gd','reader':'tests/floating_props/runtime_probe.gd',
                'formal_candidate':'tests/integration/unified_edit_formal_candidate_fail_probe.gd','formal_service':'tests/integration/unified_edit_formal_service_probe.gd'}
    previous=json.loads((dest/'preparation.json').read_text(encoding='utf-8')) if a.extend else {'rows':[],'dependency_hashes':{}}
    if any(name not in ('formal_candidate','formal_service') for name in a.refresh):raise ValueError('unsupported refresh')
    if a.refresh:
        ordinal=1
        while (dest/('preparation_before_boot_guard_%02d.json'%ordinal)).exists():ordinal+=1
        backup=dest/('preparation_before_boot_guard_%02d.json'%ordinal)
        backup.write_text(json.dumps(previous,indent=2),encoding='utf-8')
    rows=previous['rows'];dependencies=previous['dependency_hashes']
    def copy_dependency(name):
        if name in dependencies:return
        path=root/name
        if not path.is_file():raise FileNotFoundError(path)
        raw=path.read_bytes();target=runtime/name;target.parent.mkdir(parents=True,exist_ok=True)
        if target.exists() and target.read_bytes()!=raw:raise ValueError('runtime dependency differs: '+name)
        target.write_bytes(raw);dependencies[name]=hashlib.sha256(raw).hexdigest()
        if path.suffix in ('.gd','.tscn','.tres'):
            for dep in re.findall(r'res://([^"\s\)]+)',raw.decode('utf-8')):
                if dep.startswith('tests/') and (root/dep).is_file():copy_dependency(dep)
    for key,name in selections.items():
        existing=next((row for row in rows if row['name']==key),None)
        if existing:
            if hashlib.sha256((runtime/existing['generated']).read_bytes()).hexdigest()!=existing['generated_sha256']:raise ValueError('existing prepared probe changed: '+key)
            if key not in a.refresh:continue
            (dest/(key+'.before_boot_guard_%02d.gd'%ordinal)).write_bytes((runtime/existing['generated']).read_bytes());rows.remove(existing)
        copy_dependency(name);original=(root/name).read_text(encoding='utf-8');text=original
        if key in ('restore','initialization','checkpoint'):
            token='"probe":probe_case';replacement=token+',"water_numerics":{"schema":1,"solver_id":"muscl_mc_ssprk2_v1"}'
        else:
            token='root.add_child(scene)';replacement='scene.water_solver_id="muscl_mc_ssprk2_v1";root.add_child(scene)'
        if text.count(token)!=1:raise ValueError('ambiguous patch '+name)
        text=text.replace(token,replacement);target=dest/(key+'.gd')
        extra_edit=None
        if key=='formal_service':
            marker='func _sources() -> void:';extra_edit='\n\tcheck("actual_muscl_factory_"+scene.scene_key,scene.runtime.current.water.muscl!=null and scene.runtime.current.state.water_solver_id=="muscl_mc_ssprk2_v1")'
            text=text.replace(marker,marker+extra_edit)
        if key in ('formal_candidate','formal_service'):
            text=text.replace('while not scene.ready_for_ticks and scene.last_error.is_empty()', 'while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty()')
            text=text.replace('if not scene.ready_for_ticks:await _close();return','if not scene.ready_for_ticks or scene._booting:await _close();return')
        if key=='formal_candidate':
            marker='\t\tvar staged=scene.runtime.candidate'
            replacement='\t\tvar candidate_wait:=Time.get_ticks_msec()\n\t\twhile scene.runtime.candidate==null and not restore_done and Time.get_ticks_msec()-candidate_wait<15000:await process_frame\n'+marker+'\n\t\tif staged==null:\n\t\t\tcheck("candidate_created_after_props_boundary",false);observations.early_restore_error=String(restore_error);await _close();return'
            if text.count(marker)!=1:raise ValueError('ambiguous candidate wait')
            text=text.replace(marker,replacement)
        target.write_text(text,encoding='utf-8')
        rows.append({'name':key,'original':name,'original_sha256':hashlib.sha256((root/name).read_bytes()).hexdigest(),'generated':target.relative_to(runtime).as_posix(),'generated_sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'only_edit':{'from':token,'to':replacement}})
        if extra_edit:rows[-1]['additional_assertion']=extra_edit
        if key in ('formal_candidate','formal_service'):rows[-1]['precondition']='Wait for props boot transition as well as sand/water readiness before checkpoint admission. Existing test assertions unchanged.'
        if key=='formal_candidate':rows[-1]['candidate_precondition']='Await root props hold until an actual candidate exists, as in the existing formal_final restore-close probe; absent candidate produces a failure report instead of Nil access.'
    (dest/'preparation.json').write_text(json.dumps({'schema':1,'scope':'Only select the explicit MUSCL algorithm. Existing assertions unmodified. No production default change.','rows':rows,'dependency_hashes':dependencies},indent=2),encoding='utf-8')
    print('prepared',len(rows),'probes',len(dependencies),'original dependencies')


if __name__=='__main__':main()
