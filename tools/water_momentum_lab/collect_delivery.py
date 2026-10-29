import hashlib,json,re,shutil
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'test_output/water_momentum_lab'
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def ident(p):return {'path':str(p.relative_to(ROOT)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
def semantic(p):return '\n'.join(s for s in p.read_text(encoding='utf-8').splitlines() if s.strip() and not s.lstrip().startswith('#'))
def collect():
 inventory={}
 for name in ['soak_repeat_final_v2','soak_sweep_final_v2']:
  folder=OUT/name
  initial=np.fromfile(folder/'initial.rgba32f',dtype='<f4').reshape(-1,4).astype('f8')
  edited=np.fromfile(folder/'end_editing.rgba32f',dtype='<f4').reshape(-1,4).astype('f8')
  final=np.fromfile(folder/'after_release30.rgba32f',dtype='<f4').reshape(-1,4).astype('f8')
  report={'field_order':['bed','h','qx','qz'],'sand_final_delta_m3':float((final[:,0]-initial[:,0]).sum()*.015625),'water_final_delta_m3':float((final[:,1]-initial[:,1]).sum()*.015625),'release30_water_delta_m3':float((final[:,1]-edited[:,1]).sum()*.015625),'min_bed_m':float(final[:,0].min()),'min_water_m':float(final[:,1].min()),'sediment_bytes_unchanged':not any((folder/'after_release30.sediment32f').read_bytes()),'field_identities':[ident(folder/f) for f in ['initial.rgba32f','end_editing.rgba32f','after_release30.rgba32f']]}
  report['sand_budget_pass']=abs(report['sand_final_delta_m3'])<=2e-5
  (folder/'inventory_verification.json').write_text(json.dumps(report,indent=2))
  inventory[name]=report
 source=OUT/'cost_low_final_v2/sources/tests/water_momentum_lab'
 current=ROOT/'tests/water_momentum_lab'
 physical={str(p.relative_to(source)):p.read_bytes()==(current/p.relative_to(source)).read_bytes() for p in source.rglob('*') if p.is_file() and p.suffix in ['.glsl','.gdshader']}
 physical['runtime_noncomment_code_identical']=semantic(source/'lab_runtime.gd')==semantic(current/'lab_runtime.gd')
 old_profile=read(source/'profiles/default.json');new_profile=read(current/'profiles/default.json')
 physical['physical_profile_values_identical']=all(new_profile[k]==v for k,v in old_profile.items())
 packet=OUT/'packet_final_v3';checks=read(packet/'packet_suite.json')
 snapshot=packet/'sources'
 for p in [current/'lab_entry.gd',current/'lab_runtime.gd',current/'profiles/default.json',ROOT/'tools/water_momentum_lab/packet_validation.gd']:
  target=snapshot/p.relative_to(ROOT);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)
 (packet/'manifest.json').write_text(json.dumps({'command':['D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe','--path',str(ROOT),'--script','res://tools/water_momentum_lab/packet_validation.gd','--','--lab-grid=64','--lab-out=res://test_output/water_momentum_lab/packet_final_v3'],'source_snapshot_kind':'post-run; no edits during the directed probe, no independently recorded pre-run hash','source':[ident(p) for p in snapshot.rglob('*') if p.is_file()],'checks_passed':all(x['pass'] for x in checks),'release':read(packet/'release.json'),'outputs':[ident(p) for p in packet.iterdir() if p.is_file()]},indent=2))
 performance={n:read(OUT/f'{n}_final_v2/performance_analysis.json') for n in ['cost_low','cost_detail','soak_repeat','soak_sweep']}
 lifecycles=[read(OUT/f'lifecycle_{i:02d}/release.json') for i in range(10)]
 numeric=[read(OUT/f'numeric{n}_final_v2/field_verification.json') for n in [64,256]]
 passed=all(n['passed'] for n in numeric) and all(x['pass'] for x in checks) and all(physical.values()) and all(v['sand_budget_pass'] for v in inventory.values()) and all(p['gpu_edit_target_pass'] and p['frame_target_pass'] and p['nonfinite_max']==0 and all(d['passed'] for d in p['degradation'].values()) for p in performance.values())
 summary={'all_required_automated_checks_passed':passed,'recommendation':'有条件采用局部动量响应，正式接入另立任务。','scope':'已交付隔离的手动/重放实验与A0/A1/B对照；保持正式入口、公共水响应、旧排水与默认策略。','numeric_checks':sum(len(n['checks']) for n in numeric),'directed_packet_checks':len(checks),'independent_process_lifecycles':len(lifecycles),'gpu_edit_with_audit_p95_ms':performance['cost_low']['modes']['2']['edit_with_audit_ms']['p95'],'frame_p95_ms':performance['cost_low']['modes']['2']['frame_ms']['p95'],'soak_accepted':{n:p['accepted'] for n,p in performance.items() if n.startswith('soak')},'soak_water_relative_max':{n:p['water_relative_max'] for n,p in performance.items() if n.startswith('soak')},'soak_sand_final_delta_m3':{n:r['sand_final_delta_m3'] for n,r in inventory.items()},'post_metadata_physics_equivalence':physical,'limitations':'人工手感未评议；桌面捕获工具超时，已验证真实Godot窗口viewport和引擎注入输入。高台阶输运、正式工具标定、完整main负载及碰撞/保存接入不在本轮；B填沙默认幅度含5倍归一化标定，不能以强度差证明算法优越。','final_metadata_changes':'长稳后仅补充模板身份/输入时间/精确坐标日志及参数类型拒绝、缩短UI提示和注释。物理GLSL及运行时非注释代码与长稳完全相同；独立packet_final_v3验证新增输入保护、干格和限速。'}
 (OUT/'delivery_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
 print(json.dumps(summary,ensure_ascii=True,indent=2))
 assert passed

if __name__=='__main__':collect()
