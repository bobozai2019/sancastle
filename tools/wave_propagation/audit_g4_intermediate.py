"""Audit completed G4 evidence without declaring the unfinished Gate passed."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile


def main():
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();root=a.root.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False);fail=[];inputs={};raw_count=0;source_count=0
    def require(ok,reason):
        if not ok:fail.append(reason)
    def load(path):
        raw=path.read_bytes();inputs[str(path)]=hashlib.sha256(raw).hexdigest();return json.loads(raw)
    def raw_fields(value):
        nonlocal raw_count
        if isinstance(value,dict):
            if all(k in value for k in ('path','bytes','sha256')):
                path=Path(value['path']);require(path.is_file(),'missing raw '+str(path))
                if path.is_file():require(path.stat().st_size==value['bytes'] and hashlib.sha256(path.read_bytes()).hexdigest()==value['sha256'],'raw identity '+str(path));raw_count+=1
            for child in value.values():raw_fields(child)
        elif isinstance(value,list):
            for child in value:raw_fields(child)
    def probe(directory,report_name):
        nonlocal source_count
        result=load(directory/report_name);manifest=load(directory/'manifest.json');require(manifest['exit_code']==0 and manifest['outcome']=='pass','manifest '+str(directory));require(result.get('outcome')=='pass' or result.get('pass') is True,'probe '+str(directory));require(result.get('checks') and all(row['pass'] for row in result['checks']),'checks '+str(directory));raw_fields(result)
        sources=result.get('source_hashes',result.get('observations',{}).get('sources',result.get('configuration',{}).get('sources',{})))
        require(bool(sources),'sources '+str(directory))
        with zipfile.ZipFile(directory/'consumed_sources.zip') as archive:
            for name,h in sources.items():require(hashlib.sha256(archive.read(name.removeprefix('res://'))).hexdigest()==h,'source archive '+str(directory)+'/'+name);source_count+=1
        return result
    probe(root/'g4_restore_01','result.json')
    for name,count in [('g4_failure_matrix_01',11),('g4_formal_matrix_01',10),('g4_service_matrix_03',2)]:
        directory=root/name;suite=load(directory/'result.json');require(suite['outcome']=='pass' and len(suite['rows'])==count,'matrix '+name)
        for row in suite['rows']:
            require(row['outcome']=='pass' and not row['source_drift'],'row '+name+'/'+row['id']);probe(directory/row['id'],Path(row['report']).name)
    for name in ['g4_bottle_flow_01','g4_bottle_delay_01']:
        result=probe(root/name,'result.json');wave=result['observations']['wave_samples'];require(wave['maximum_force_sample_age_s']<=.15+1e-6,'existing sample age '+name)
        final=result['observations']['final'];actual=final['actual_time_s']['1'];admitted=final['admitted_time_s'];require(abs(actual-admitted)<=max(1e-6,admitted*1e-7),'real Jolt budget '+name)
    directory=root/'g4_native_restart_01';restart=load(directory/'result.json');comparison=load(directory/'comparison.json');require(restart['outcome']=='pass' and comparison['outcome']=='pass' and all(row['pass'] for row in comparison['checks']),'cold restart')
    for item in comparison['inputs'].values():require(hashlib.sha256(Path(item['path']).read_bytes()).hexdigest()==item['sha256'],'native container identity')
    for mode in ['seed','resume']:
        data=load(directory/mode/'data/result.json');require(data['outcome']=='pass' and all(row['pass'] for row in data['checks']) and not data['source_drift'],'cold process '+mode);raw_fields(data)
        with zipfile.ZipFile(directory/mode/'consumed_sources.zip') as z:
            for name,h in data['configuration']['sources'].items():require(hashlib.sha256(z.read(name.removeprefix('res://'))).hexdigest()==h,'cold source '+mode+'/'+name);source_count+=1
    result={'schema':1,'outcome':'pass' if not fail else 'fail','failures':fail,'scope':'Intermediate only: T04 G01/G02/G04 evidence; G03 historical source compatibility and G4 overall remain incomplete. No G5 or cost assertion.','raw_field_identity_checks':raw_count,'source_archive_member_checks':source_count,'input_hashes':inputs,'analysis_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    (out/Path(__file__).name).write_bytes(Path(__file__).read_bytes());(out/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps({k:v for k,v in result.items() if k!='input_hashes'},indent=2));raise SystemExit(bool(fail))


if __name__=='__main__':main()
