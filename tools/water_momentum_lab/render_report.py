"""Static evidence plots and a self-contained local delivery report."""
import base64,json,html
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'test_output/water_momentum_lab';DELIVERY=Path('C:/Users/18205/Documents/Codex/2026-10-19/go/outputs')
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def embed(p):return 'data:image/png;base64,'+base64.b64encode(p.read_bytes()).decode()

def build():
 DELIVERY.mkdir(exist_ok=True,parents=True)
 effect=read(OUT/'numeric256_final_v2/effect_analysis.json')
 plt.rcParams.update({'font.size':10,'axes.spines.top':False,'axes.spines.right':False})
 fig,ax=plt.subplots(2,3,figsize=(13,7),layout='constrained')
 colors=['#677386','#d19436','#168d9b']
 for s in effect['series']:
  col=s['op'];mode=s['mode'];label=['A0 natural','A1 raised bed','B signed impulse'][mode]
  ax[0,col].plot(s['t'],np.asarray(s['roi_m3'])-s['roi_m3'][0],label=label,color=colors[mode])
  ax[1,col].plot(s['flow_t'],s['net_outflow'],label=label,color=colors[mode])
 for i,title in enumerate(['Dig','Fill','Balanced shovel']):
  ax[0,i].set_title(title);ax[0,i].set_ylabel('ROI water change (m³)');ax[1,i].set_ylabel('ROI net outflow (m³/s)')
  for j in range(2):ax[j,i].set_xlabel('Actual completed simulation time (s)');ax[j,i].grid(alpha=.2);ax[j,i].axhline(0,color='#999',lw=.5)
 ax[0,0].legend();fig.suptitle('Fixed 1.5 m ROI, closed lake; positive flow means water leaves ROI')
 chart=OUT/'effect_curves.png';fig.savefig(chart,dpi=150);plt.close(fig)
 performance={name:read(OUT/f'{name}_final_v2/performance_analysis.json') for name in ['cost_low','cost_detail','soak_repeat','soak_sweep']}
 fig,axes=plt.subplots(1,2,figsize=(11,3.6),layout='constrained')
 for name,color in [('soak_repeat','#168d9b'),('soak_sweep','#d19436')]:
  bins=performance[name]['ten_second_timing_bins']
  axes[0].plot([b['start_s'] for b in bins],[b['edit_p95_ms'] for b in bins],label=name,color=color)
  axes[1].plot([b['start_s'] for b in bins],[b['frame_p95_ms'] for b in bins],label=name,color=color)
 axes[0].axhline(2,color='#c54',ls='--',label='2 ms target');axes[1].axhline(33.3,color='#c54',ls='--',label='33.3 ms target')
 for ax,title in zip(axes,['GPU edit + required audit P95 (ms)','Frame P95 (ms)']):ax.set_title(title);ax.set_xlabel('Wall time / 10s bins');ax.grid(alpha=.2);ax.legend()
 chart2=OUT/'soak_cost_curves.png';fig.savefig(chart2,dpi=150);plt.close(fig)
 numerical=[read(OUT/f'numeric{n}_final_v2/field_verification.json') for n in [64,256]]
 p=performance['cost_low']['modes']['2'];d=performance['cost_detail']['modes']['2']
 rows=''
 for name in performance:
  x=performance[name];m=x['modes']['2']
  rows+=f'<tr><td>{name}</td><td>{m["edit_with_audit_ms"]["p95"]:.3f}</td><td>{m["frame_ms"]["p95"]:.2f}</td><td>{x["accepted"]}</td><td>{x["nonfinite_max"]:.0f}</td></tr>'
 checks=sum(len(n['checks']) for n in numerical)
 conclusion=read(OUT/'delivery_summary.json')
 command='& "D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --path "D:/godot/project/sandcastle" "res://scenes/experiments/water_momentum_lab.tscn"'
 preview=OUT/'visual_delivery/pointer_view_2.png'
 body=f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>水动量独立实验交付</title><style>
body{{font:16px/1.7 system-ui;background:#f3f6fa;color:#203247;max-width:1180px;margin:32px auto;padding:0 24px}}h1{{font-size:30px}}h2{{font-size:22px;margin-top:32px}}.card{{background:white;border-radius:12px;padding:24px;margin:20px 0}}img{{width:100%;border-radius:8px}}table{{width:100%;border-collapse:collapse}}td,th{{text-align:left;padding:9px;border-bottom:1px solid #ddd}}pre{{white-space:pre-wrap;overflow-wrap:anywhere;background:#edf2f6;padding:16px}}.note{{color:#53677d}}code{{font-size:14px}}</style>
<h1>水编辑速度／动量独立实验</h1><p>2026-10-19 · GTX 1050 · Godot 4.7.2 · D3D12 · 1280×720 · VSync1</p>
<div class="card"><strong>{html.escape(conclusion['recommendation'])}</strong><p>{html.escape(conclusion['scope'])}</p><p>64²／256²共{checks}项独立检查通过；真实窗口成本与两组五分钟长稳证据在下方。正式入口、公共水响应与默认策略未改。</p></div>
<h2>运行与操作</h2><pre>{html.escape(command)}</pre><p>左键拖动使用所选挖／填／铲工具，右键填沙。空格暂停，N单个CFL水步，R复位。下拉框切换A0／A1／B、初态及水深／速度／床面视图。重放按钮运行固定4m轨迹，导出按钮保存同完成态场、指标和窗口图像。</p>
<p class="note">场景：D:\\godot\\project\\sandcastle\\scenes\\experiments\\water_momentum_lab.tscn。默认gain=1m/s，半径.75m。Godot自建适配，不声称是原作完整水模拟。</p>
<div class="card"><img src="{embed(preview)}"><p class="note">引擎注入鼠标事件通过实际viewport拾取与命令路径；自动测试，未冒称人类手动评议。</p></div>
<h2>效果与归因</h2><div class="card"><img src="{embed(chart)}"><p>B在挖沙区也产生即时速度响应，A1只响应抬床。填沙B的默认归一化产生约5倍A1冲量；实际GPU场满足A1≈0.2B，最大分量差3.73e-9m²/s，因此更强的填沙外流不能单独证明算法更优。所有模式后续共用同一水核，水量变化来自输运。</p><p>凹坑蓄水合理；20／80cm平台负例保留。局部冲量没有替换浅水输运，正式接入前仍需独立验证高台阶、工具增益、碰撞／保存与完整main负载。</p></div>
<h2>成本与长稳</h2><div class="card"><table><thead><tr><th>测试</th><th>B编辑+审计P95 / ms</th><th>整帧P95 / ms</th><th>接纳样本</th><th>非有限值</th></tr></thead><tbody>{rows}</tbody></table><img src="{embed(chart2)}"><p>低扰动与详细模式各三轮交替A0/A1/B，90秒；固定点和扫域分别300秒可逆铲动，再停手观察30秒。GPU时间来自后端纳秒时间戳；帧间隔按单调时钟相邻_process回调计算，Godot delta可能平滑。异步回执往返不是GPU成本。</p></div>
<h2>限制与复验</h2><p>{html.escape(conclusion['limitations'])}</p><p>实验文档与用法：<code>D:\\godot\\project\\sandcastle\\tests\\water_momentum_lab\\README.md</code>。验收：<code>D:\\godot\\project\\sandcastle\\task\\sandcastle_water_momentum_lab\\验收</code>。原始证据：<code>D:\\godot\\project\\sandcastle\\test_output\\water_momentum_lab</code>。每轮manifest保存命令、源码快照、hash、环境和实际退出状态。被替代／中断的早期结果保留。</p>
<pre>{html.escape(json.dumps({k:v for k,v in conclusion.items() if k not in ['recommendation','scope','limitations']},ensure_ascii=False,indent=2))}</pre></html>'''
 target=DELIVERY/'water_momentum_lab_delivery.html';target.write_text(body,encoding='utf-8');print(target)

if __name__=='__main__':build()
