"""Compare E zero-speed trajectory with frozen C, and initial geometry for all speeds."""
import argparse, hashlib, json, csv
from pathlib import Path
p=argparse.ArgumentParser(); p.add_argument('combined',type=Path); p.add_argument('c',type=Path); a=p.parse_args()
data=json.loads((a.combined/'velocity_curve_probe.json').read_text(encoding='utf-8-sig'))
fields=['rock','sand','water','momentum_x','momentum_z','sediment','wetness','compaction','obstacle','flux','published_sand','published_water']
records=[]
for row in data['rows']:
    if row['signed_speed_m_s'] != 0 and row['completed_tick'] != 0: continue
    for field in fields:
        if row['signed_speed_m_s'] != 0 and field in ['momentum_x','momentum_z']: continue
        e=row['prefix']+'_'+field+'.bin'
        c=f"{row['grid']}_C_tick{row['completed_tick']:03d}_{field}.bin"
        eh=hashlib.sha256((a.combined/e).read_bytes()).hexdigest()
        ch=hashlib.sha256((a.c/c).read_bytes()).hexdigest()
        records.append(dict(e=e,c=c,equal=eh==ch,e_sha256=eh,c_sha256=ch))
ok=data['pass'] and all(x['equal'] for x in records)
report=dict(pass_all=ok, scope='E0 trajectory all12 fields; E nonzero tick0 all except q',count=len(records),files=records)
(a.combined/'C_E_equivalence.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
with (a.combined/'combined_curve_metrics.csv').open('w',newline='',encoding='utf-8') as f:
    keys=['grid','signed_speed_m_s','completed_tick','actual_sim_s','center_h_m','roi_max_h_m','roi_mean_h_m','roi_migration_m3','eta_peak_wet_m','max_speed_m_s','water_relative_error','sand_absolute_error_m3','sediment_absolute_error_m3','max_substeps']
    w=csv.DictWriter(f,fieldnames=keys); w.writeheader()
    for row in data['rows']: w.writerow({k:row[k] for k in keys})
index=dict(tool=str(Path(__file__).resolve()),tool_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),arguments=[str(a.combined),str(a.c)],files=[])
for n in ['C_E_equivalence.json','combined_curve_metrics.csv']:
    f=a.combined/n; index['files'].append(dict(name=n,bytes=f.stat().st_size,sha256=hashlib.sha256(f.read_bytes()).hexdigest()))
(a.combined/'post_analysis_index.json').write_text(json.dumps(index,indent=2),encoding='utf-8')
print(json.dumps(dict(pass_all=ok,count=len(records))))
raise SystemExit(0 if ok else 1)
