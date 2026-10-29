"""Analyze retained float fields, independent linear-wave prediction and profiles."""
import argparse
import json
from pathlib import Path
import hashlib
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

plt.rcParams['font.sans-serif'] = ['Microsoft YaHei', 'DejaVu Sans']
plt.rcParams['axes.unicode_minus'] = False

X = (np.arange(256)+.5-128)*.125
XX, ZZ = np.meshgrid(X, X)
R = np.hypot(XX, ZZ)
SEG_R = np.hypot(XX, ZZ-np.clip(ZZ, -.5, .5))


def fields(s):
    return {k:np.fromfile(v['path'], dtype='<f4').reshape(256,256).astype(float)
            for k,v in s['fields'].items() if k not in ('decision','control')}


def eta(f):
    return f['rock']+f['sand']+f['water']


def amplitude(f, wavelength):
    # Central eight metres; complete wavelengths, far from the physical boundary
    # disturbance over these 4 seconds. Uniform Z excludes geometric spreading.
    mask = abs(X)<4
    signal = f['water'][128,mask]
    return abs(2*np.mean((signal-np.mean(signal))*np.exp(-2j*np.pi*X[mask]/wavelength)))


def inventory(f):
    wet = f['water'] > .001
    speed = np.hypot(f['momentum_x'], f['momentum_z'])/np.maximum(f['water'],.001)
    return {'water_m3':float(f['water'].sum()*.125**2),
            'min_h_m':float(f['water'].min()), 'max_h_m':float(f['water'].max()),
            'max_speed_m_s':float(speed[wet].max(initial=0)),
            'finite':bool(all(np.isfinite(x).all() for x in f.values()))}


def rings(delta):
    return [{'range_m':[a,b], 'max_abs_eta_mm':float(np.max(abs(delta[(SEG_R>=a)&(SEG_R<b)]))*1000)}
            for a,b in [(0,.75),(.75,1.5),(1.5,2.5),(2.5,4),(4,6)]]


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('root', type=Path)
    args=ap.parse_args()
    report={'wave_cases':{},'shovel_cases':{},'sources':{},'excluded_evidence':[
        'flat_v1 shovel_B/shovel_no_impulse used legacy schema-2 default policy=3/speed=0; excluded from B comparison. Raw results retained unchanged. Replaced by flat_shovel_v2.']}
    flat=json.loads((args.root/'flat_v1/diagnosis.json').read_text(encoding='utf-8'))
    assert flat['pass'] and not flat['source_drift']
    fig, axes=plt.subplots(1,2,figsize=(11,4.4))
    flat_cases=[c for c in flat['cases'] if not c['id'].startswith('shovel')]
    repeat_path=args.root/'flat_shovel_v2/diagnosis.json'
    if repeat_path.exists():
        repeated=json.loads(repeat_path.read_text(encoding='utf-8'))
        assert repeated['pass'] and not repeated['source_drift']
        flat_cases += repeated['cases']
    for case in flat_cases:
        snaps=case['snapshots']
        initial=fields(snaps[0])
        initial_mass=inventory(initial)['water_m3']
        rows=[]
        for s in snaps:
            f=fields(s)
            inv=inventory(f)
            assert inv['finite'] and inv['min_h_m']>=0
            rows.append({'label':s['label'],'t':s['time_s'],**inv,
                         'mass_relative_error':(inv['water_m3']-initial_mass)/initial_mass,
                         'rings':rings(eta(f)-(.5 if case['id']=='radial_pulse' else eta(initial)))})
        if case['id'].startswith('sine'):
            lam=case['initial_condition']['wavelength_m']
            a0=amplitude(initial,lam)
            c=np.sqrt(9.81*.1)
            C=c*(1/30)/.125
            theta=2*np.pi*.125/lam
            G=complex(1-C*(1-np.cos(theta)), -C*np.sin(theta))
            for row,s in zip(rows,snaps):
                row['amplitude_ratio']=amplitude(fields(s),lam)/a0
                row['linear_discrete_prediction']=abs(G)**s['tick']
            report['wave_cases'][case['id']]={'wavelength_m':lam,'expected_speed_m_s':c,'C':C,'rows':rows}
            axes[0].plot([r['t'] for r in rows],[r['amplitude_ratio'] for r in rows],'o-',label=f'GPU 实测：波长 {lam:g} m')
            axes[0].plot([r['t'] for r in rows],[r['linear_discrete_prediction'] for r in rows],'--',label=f'离散算法预测：{lam:g} m')
        else:
            report['shovel_cases'][case['id']]=rows
            if case['id']=='radial_pulse':
                for s in snaps:
                    if s['label'] not in ['tick_015','tick_030','tick_060','tick_120']:continue
                    f=fields(s)
                    bins=np.arange(0,6.125,.125)
                    profile=np.array([np.mean((eta(f)-.5)[(R>=a)&(R<b)]) for a,b in zip(bins[:-1],bins[1:])])
                    axes[1].plot((bins[:-1]+bins[1:])/2, profile*1000,label=f"{s['time_s']:.1f} s")
    axes[0].set(xlabel='已完成模拟时间（秒）',ylabel='剩余振幅 / 初始振幅',title='相同水深和振幅，仅改变波长',ylim=(0,1.03))
    axes[0].legend(fontsize=8);axes[0].grid(alpha=.3)
    axes[1].set(xlabel='距扰动中心（米）',ylabel='相对静水面的起伏（毫米）',title='局部凹陷确实形成向外传播的波',xlim=(0,6),ylim=(-.8,.65))
    axes[1].legend(fontsize=8);axes[1].grid(alpha=.3)
    fig.tight_layout();fig.savefig(args.root/'wave_decay.png',dpi=170);plt.close(fig)
    main_path=args.root/'main_v1/diagnosis.json'
    if main_path.exists():
        main_data=json.loads(main_path.read_text(encoding='utf-8'))
        assert main_data['pass'] and not main_data['source_drift']
        cases={c['id']:c for c in main_data['cases']}
        base={s['label']:s for s in cases['main_control']['snapshots']}
        edits=cases['main_shovel']['snapshots']
        before=fields(edits[0]); edited=fields(edits[1])
        changed=abs(edited['sand']-before['sand'])>1e-7
        qchange=np.hypot(edited['momentum_x']-before['momentum_x'],edited['momentum_z']-before['momentum_z'])
        report['main_input']={'water_exactly_unchanged':bool(np.array_equal(before['water'],edited['water'])),
            'changed_bed_cells':int(changed.sum()), 'bed_delta_min_m':float((edited['sand']-before['sand']).min()),
            'bed_delta_max_m':float((edited['sand']-before['sand']).max()),
            'initial_depth_changed_cells_min_m':float(before['water'][changed].min()),
            'initial_depth_changed_cells_max_m':float(before['water'][changed].max()),
            'max_added_speed_m_s':float((qchange/np.maximum(before['water'],.001)).max()),
            'water_initial_m3':inventory(before)['water_m3']}
        delta_bed=edited['sand']-before['sand']
        spectral_power=abs(np.fft.fft2(delta_bed))**2
        spectral_power[0,0]=0
        freq=np.fft.fftfreq(256,.125)
        radial_freq=np.hypot(freq[:,None],freq[None,:])
        report['main_input']['height_squared_spectral_fraction_wavelength_below_2m']=float(spectral_power[radial_freq>=.5].sum()/spectral_power.sum())
        report['main_input']['baseline_restored_fields_identical']=all(np.array_equal(before[k],fields(base['before'])[k]) for k in before)
        rows=[]
        fig,axes=plt.subplots(1,2,figsize=(11,4.4))
        for s in edits:
            control=fields(base.get(s['label'],base['before']))
            f=fields(s);delta=eta(f)-eta(control)
            near=(abs(XX)<4)&(abs(ZZ)<4)
            delta_u=np.hypot(f['momentum_x']/np.maximum(f['water'],.001)-control['momentum_x']/np.maximum(control['water'],.001),
                             f['momentum_z']/np.maximum(f['water'],.001)-control['momentum_z']/np.maximum(control['water'],.001))
            rows.append({'label':s['label'],'t':s['time_s'],'rings':rings(delta),
                'local_max_abs_eta_mm':float(abs(delta[near]).max()*1000),
                'local_max_delta_speed_m_s':float(delta_u[near].max()),
                'delta_water_m3':float((f['water']-control['water']).sum()*.125**2),
                'inventory':inventory(f)})
            if s['label'] in ['edited','tick_015','tick_030','tick_060','tick_120']:
                # Mean of the middle two rows, perpendicular to the shovel track.
                axes[0].plot(X,delta[127:129].mean(axis=0)*1000,label=f"{s['time_s']:.1f} s")
        edited_delta=eta(edited)-eta(before)
        im=axes[1].imshow(edited_delta*1000,origin='lower',extent=(-16,16,-16,16),cmap='RdBu_r',vmin=-150,vmax=150)
        fig.colorbar(im,ax=axes[1],label='毫米',fraction=.046,pad=.04)
        axes[1].set(xlim=(-2,2),ylim=(-2,2),xlabel='X（米）',ylabel='Z（米）',title='铲子初始扰动：窄沟与两侧沙肩')
        axes[0].set(xlim=(-4,4),xlabel='横穿铲痕的 X 坐标（米）',ylabel='相对未挖沙对照的水面变化（毫米）',title='主场景实际铲子，动量 B，力度 0.25')
        axes[0].legend(fontsize=8);axes[0].grid(alpha=.3)
        fig.tight_layout();fig.savefig(args.root/'main_shovel.png',dpi=170);plt.close(fig)
        report['main_response']=rows
    report['flat_mass_relative_error_max']=max(abs(r['mass_relative_error']) for c in report['wave_cases'].values() for r in c['rows'])
    report['discrete_amplitude_prediction_max_absolute_error']=max(abs(r['amplitude_ratio']-r['linear_discrete_prediction']) for c in report['wave_cases'].values() for r in c['rows'])
    # Verify user-facing running project is text-equivalent; raw hashes retained.
    project=Path(__file__).resolve().parents[2]
    running=Path('D:/godot/openproject/sancastle')
    for path in ['shaders/simulation/shallow_edge_flux.glsl','shaders/simulation/shallow_update_state.glsl',
                 'scripts/simulation/unified_edit/water_response.glsl','scripts/simulation/unified_edit/water.gd',
                 'scripts/beach/unified_playable_entry.gd','assets/unified_edit/presentation/main.json',
                 'assets/water_material_natural_candidate/async_rdc_water.gdshader','assets/unified_edit/shovel_v1.tres','scenes/main.tscn']:
        a=(project/path).read_bytes();b=(running/path).read_bytes()
        report['sources'][path]={'workspace_sha256':hashlib.sha256(a).hexdigest(),'running_copy_sha256':hashlib.sha256(b).hexdigest(),
                                'equal_after_newline_normalization':a.replace(b'\r\n',b'\n')==b.replace(b'\r\n',b'\n')}
    (args.root/'analysis.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    rows_html=''.join('<tr><td>'+str(c['wavelength_m'])+' m</td>'+''.join(f"<td>{r['amplitude_ratio']*100:.2f}%</td>" for r in c['rows'] if r['label'] in ['tick_015','tick_030','tick_060','tick_120'])+'</tr>' for c in report['wave_cases'].values())
    page=f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>水波传播定位 Q-WAVE-01</title>
<style>body{{max-width:1080px;margin:40px auto;padding:0 24px;font:16px/1.7 "Microsoft YaHei",sans-serif;color:#203040;background:#f5f7fa}}article{{background:white;padding:32px;border-radius:12px}}h1{{font-size:28px}}h2{{font-size:21px;margin-top:30px}}table{{border-collapse:collapse;width:100%}}td,th{{border:1px solid #d6e0e8;padding:9px;text-align:left}}img{{width:100%;height:auto}}code{{background:#edf2f6;padding:2px 5px}}.note{{color:#566570}}a{{color:#1165a2}}</style><article>
<h1>水波传播定位：短波在一阶通量中快速衰减</h1>
<p>2026-10-20 · Q-WAVE-01 · 仅诊断，正式 shader、场景、profile 与算法均未修改。</p>
<p><b>确定的瓶颈是现有一阶 Rusanov 通量的短波耗散。</b>平底、无侵蚀、无潮汐、无材质的生产 GPU 数值核对照中，1 m 波长在 1 秒后仅保留 16.3% 振幅，4 m 波长保留 89.4%。GPU 结果与离散算法的线性耗散预测吻合。</p>
<h2>证据与归因</h2><table><tr><th>候选原因</th><th>观测</th><th>结论与范围</th></tr>
<tr><td>浅水方程不产生外传波</td><td>径向凹陷波随时间移到更大的半径；主场景 4 秒时仍在 4–6 m 距离带测到约 2.27 mm 扰动。</td><td>C3：本实现有真实外传波。</td></tr>
<tr><td>数值耗散</td><td>平底均匀水深 0.1 m、同样 0.1 mm 初始振幅、仅改变波长；单向波消除了径向扩散的振幅下降。</td><td>C3：一阶通量强烈衰减短波。误差主要落在求解器，显示不是唯一原因。</td></tr>
<tr><td>铲子没有施加冲量</td><td>主场景水深在编辑瞬间逐格不变；新增速度最大 0.1703 m/s。平底 B / 力度零对照具有不同速度与外传振幅。</td><td>C3：冲量生效。力度零仍由床面变化激发水波。</td></tr>
<tr><td>铲子源波形</td><td>50 cm 沟宽跨约 4 格；实际编辑水面为中央凹陷与两侧隆起；高度平方的空间谱有 92.57% 位于波长小于 2 m 的部分。</td><td>C3：初始扰动偏短；C2：与已测短波耗散共同解释迅速变平。空间谱不是完整水波能量账本。</td></tr>
<tr><td>显示发布丢失或旧完成态</td><td>全部采样时刻的公开水深、床沙与动量和权威字段逐字节相等。</td><td>C3：这些采样中未发生字段丢失；材质对毫米级残波可见性的影响尚未量化。</td></tr>
<tr><td>侵蚀、干格清零、限速或水量丢失</td><td>强衰减在关闭侵蚀、全湿、微小速度的平底样例中复现，封闭水量相对误差极小。</td><td>这些因素不是平底短波衰减的必要条件；未声称主场景岸边因素完全无贡献。</td></tr></table>
<h2>纯波传播：剩余振幅</h2><table><tr><th>波长</th><th>0.5 秒</th><th>1 秒</th><th>2 秒</th><th>4 秒</th></tr>{rows_html}</table>
<img src="wave_decay.png" alt="短波与长波衰减，径向波的传播">
<p>计算：H=0.1 m，Δx=0.125 m，Δt=1/30 s，c=√(gH)，C=cΔt/Δx≈0.2641。对小振幅右行单一频率波，当前离散的放大因子为 <code>G=1−C(1−cos θ)−i C sin θ</code>，θ=2πΔx/λ，预期剩余振幅为 |G|ⁿ。解析浅水线性行波的振幅保持不变；这里的预测曲线专指离散误差。最大 GPU/离散预测振幅比绝对差为 {report['discrete_amplitude_prediction_max_absolute_error']:.6f}。4 秒末的 1 m 波已接近 float 精度，不能据其末值作高精度拟合。</p>
<h2>真实主场景</h2><p>正式 <code>scenes/main.tscn</code>，固定初态，主场景边界、侵蚀、白沫与碎石保持配置；铲痕从 (0,−0.5) 到 (0,0.5)，沟宽 0.5 m、深度 0.15 m、肩宽 0.5 m，策略 2、力度 0.25。两轮从相同检查点开始，初始字段逐字节相等；以相同完成 tick 的未挖沙样例相减。道具在暂停状态，未测运动手感。</p>
<p>附近 8×8 m 区域的最大水面差：编辑后 136.27 mm → 0.5 秒 20.79 mm → 1 秒 11.11 mm → 2 秒 7.22 mm → 4 秒 3.18 mm。4 秒时离铲痕 4–6 m 带仍有约 2.27 mm 扰动。这个总衰减含几何扩散、床面/岸边与非线性影响，不能全部归为数值耗散。</p>
<img src="main_shovel.png" alt="主场景铲子剖面与初始扰动">
<h2>定位到的源码</h2><p><code>shaders/simulation/shallow_edge_flux.glsl:53–56,75–78</code>：左右格常值状态加 Rusanov 差分耗散项。<code>shallow_update_state.glsl:118–130</code>：水深/动量更新及干格、限速保护。<code>scripts/simulation/unified_edit/water_response.glsl</code>：按实际床面差注入动量。<code>assets/water_material_natural_candidate/async_rdc_water.gdshader:193–310</code>：完成态空间重构，无独立逐帧水面衰减。</p>
<h2>复验与产物</h2><p>运行 <code>python tools/wave_propagation/run.py flat &lt;全新目录&gt;</code> 或 <code>main</code>；<code>flat_shovel</code>仅复验铲子控制。固定 dt 通过原 Pipeline.request_tick 提交；每次等待队列完成再采样，时间来自 advanced_time_s。每轮保留命令、引擎 hash、probe 源码、运行配置/source hash、GPU 控制/decision 与原始 float 字段。采样有同步读回，因此不用于性能判断。</p>
<p><a href="analysis.json">分析数据</a> · <a href="flat_v1/diagnosis.json">纯波原始索引</a> · <a href="flat_shovel_v2/diagnosis.json">铲子力度对照索引</a> · <a href="main_v1/diagnosis.json">主场景索引</a></p>
<p class="note">初轮 flat_v1 中两个铲子样例误用了 legacy schema-2 的默认策略 3/力度 0，已从结论中剔除，由 flat_shovel_v2 替代；纯波与正式主场景样例不受影响。原始失败/错配证据保持原样。分析 JSON 明确标记排除项。</p>
<p class="note">用户正在运行的 D:/godot/openproject/sancastle 与工作区所核对的 9 个关键文件在换行归一后相同，原始 hash 已记录；没有读取当前进程内存、当前工具值或已编辑沙场，因此本报告是相同磁盘实现的固定初态复现，不冒称对用户当前那一铲的精确重放。未改正式实现；下一步候选应针对短波数值耗散作隔离对照。</p></article></html>'''
    (args.root/'report.html').write_text(page,encoding='utf-8')
    for name,case in report['wave_cases'].items():
        print(name,[(round(r['t'],2),round(r['amplitude_ratio'],5)) for r in case['rows']])
    print('main_input',json.dumps(report.get('main_input',{})))


if __name__=='__main__':main()
