"""Bounded-memory comparison of complete current-layout state archives."""
import json,zipfile,hashlib
from pathlib import Path

def compare(a_dir,b_dir,output):
    a,b=[json.loads((d/'variant.json').read_text(encoding='utf-8')) for d in [a_dir,b_dir]]
    errors=[]; differences=[]
    with zipfile.ZipFile(a_dir/'states.zip') as za,zipfile.ZipFile(b_dir/'states.zip') as zb:
        na,nb=za.namelist(),zb.namelist()
        if set(na)!=set(nb) or len(na)!=len(set(na)) or len(nb)!=len(set(nb)):errors.append('member_inventory')
        for name in sorted(set(na)|set(nb)):
            if name not in na or name not in nb or za.read(name)!=zb.read(name):differences.append(name)
        for d,z in [(a,za),(b,zb)]:
            for row in d['observations']:
                for meta in row['fields'].values():
                    data=z.read(meta['member'])
                    if len(data)!=meta['bytes'] or ('sha256' in meta and hashlib.sha256(data).hexdigest()!=meta['sha256']):errors.append(meta['member'])
    def observations(d):return [{k:v for k,v in x.items() if k not in ['fields','cache']} for x in d['observations']]
    matched=observations(a)==observations(b)
    for p in [a_dir,b_dir]:
        m=json.loads((p/'manifest.json').read_text(encoding='utf-8'))
        if m['exit_code'] or m['source_drift'] or not m['user_unchanged']:errors.append(str(p)+':manifest')
        if any(x.startswith(('ERROR:','SCRIPT ERROR:')) for x in (p/'run.log').read_text(encoding='utf-8',errors='replace').splitlines()):errors.append(str(p)+':engine_error')
    result={'pass':a['pass'] and b['pass'] and bool(a['observations']) and not differences and not errors and matched and a.get('injections')==b.get('injections'), 'paired_ticks':len(a['observations']),'members':len(na),'differences':differences,'errors':errors,'observations_equal':matched,'scope':'All raw decompressed ZIP members and their declared field lengths/hashes; identical current RG32F layout, no exclusions or numerical tolerance.'}
    output.write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result),flush=True)
    if not result['pass']:raise AssertionError(result)
