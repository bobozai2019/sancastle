"""Join all shader identities and three replay timestamp runs into a static index."""
import collections
import hashlib
import json
import math
import re
import statistics
from pathlib import Path

ROOT=Path('D:/godot/project/sandcastle')
BASE=ROOT/'docs/competitor/evidence/shader_execution_20261025'
OUT=BASE/'summary_v1'
OUT.mkdir(exist_ok=False)

def identity(p):
    return dict(path=p.as_posix(),bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest())

def verify(x):
    a=identity(Path(x['path']))
    assert a['bytes']==x['bytes'] and a['sha256']==x['sha256'],x['path']

manifests={}
for name in ['selected_v1','post_v1','graphics_v1','views_v2','timing_v1']:
    m=json.loads((BASE/name/'manifest.json').read_text('utf-8'))
    assert m.get('pass',m.get('success')),name
    verify(m['source']); verify(m['script'])
    for item in m.get('exports',[]):verify(item)
    manifests[name]=m
g=manifests['graphics_v1']
core=json.loads((BASE/'analysis_v1/analysis.json').read_text('utf-8'))
assert identity(BASE/'analysis_v1/analyze_script.py')['sha256']==core['script']['sha256']
runs=[]
for run in manifests['timing_v1']['runs']:
    verify(run['data'])
    data=json.loads(Path(run['data']['path']).read_text())
    assert all(math.isfinite(x['seconds']) and x['seconds']>=0 for x in data)
    runs.append({x['event']:1000*x['seconds'] for x in data})

def timing(ids):
    assert all(e in r for r in runs for e in ids)
    totals=[sum(r[e] for e in ids) for r in runs]
    return dict(runs_ms=totals,median_ms=statistics.median(totals),min_ms=min(totals),max_ms=max(totals))

notes={
 '1667_vs':'48 B 实例/索引读取，四元数变换、出现尺度、视向输出',
 '1667_ps':'视向图集取样、透明裁剪、深度重建；植被仅做绘制结构分析',
 '1677_vs':'16 B 实例/索引读取、缩放与阴影偏移',
 '1677_ps':'常量输出的深度配套 PS；其绘制成本主要不能由两条 PS 指令解释',
 '1790_vs':'泡沫状态/索引读取、水平片缩放与深度投影',
 '1790_ps':'圆片范围裁剪',
 '2314_vs':'打包沙场取数与几何高度/法线解码，深度绘制',
 '2638_ps':'4 次沙场读取、手工双线性、高度边界裁剪',
 '2647_ps':'4 次水场读取、amount/floor 解码、水面边界裁剪',
 '2689_vs':'沙/水场多点读取、解码、插值与几何输出',
 '2689_ps':'低分辨率颜色/高度生产绘制；4 次空气场读取、2 次纹理采样',
 '2974_ps':'普通几何的颜色/高度生产绘制；共享空气场和光照输入',
 '2992_ps':'同类颜色/高度生产变体；常量差异不等于新算法',
 '3536_vs':'几何变换并输出位置/高度',
 '3536_ps':'高度值写入，供障碍场消费',
 '4906_vs':'沙高/打包法线解码，水状态手工双线性，传给 PS',
 '4906_ps':'颗粒/湿色、双路 3D 焦散、公共光照、空气衰减与阴影',
 '5155_ps':'纹理取样与颜色/光照运算；具体对象业务身份不分析',
 '5215_ps':'水场双线性、可见水深阈值与侧面范围掩码',
 '5228_ps':'沙场/空气场多点读取和 4 处材质/光照采样',
 '5265_ps':'空气场插值、阴影及表面光照',
 '5286_ps':'沙侧面按沙高裁剪，空气场衰减、条纹采样和光照',
 '5299_ps':'普通物体材质，空气场插值、纹理/共享光照/阴影',
 '5733_vs':'沙粒索引与 16 B 状态驱动实例几何',
 '5746_vs':'碎石索引与 16 B 状态驱动实例几何',
 '5760_vs':'48 B 实例、旋转及出现尺度',
 '5760_ps':'视向图集材质/深度/法线重建与空气/公共光照；仅视觉结构',
 '6003_ps':'场景颜色复制',
 '6027_vs':'4 邻水面高度平均、中心打包法线/速度解码及沙状态读取',
 '6027_ps':'3 次细法线 + 2 次深度 + 场景色 + 阴影；吸收/Fresnel/窄高光',
 '6184_ps':'水侧面按 floor/amount 裁剪，深度重建与 RGB 吸收',
 '6196_vs':'可见索引→泡沫状态→水平片几何，强度控制尺度',
 '6196_ps':'圆片裁剪、中心 alpha≤0.2、空气衰减/公共光照/阴影',
 '6212_ps':'深度差软交界、圆形衰减与颜色输出',
 '6229_ps':'常量输出辅助 pass',
 '6241_ps':'横向五点加权滤波', '6251_ps':'纵向五点加权滤波',
 '6261_ps':'两输入阈值/掩码合成',
 '6275_ps':'体积散射：视线最多 52 步，光照方向最多 12 步，水/空气/3D 噪声/阴影',
 '6286_ps':'横向五点滤波', '6297_ps':'纵向五点滤波', '6309_ps':'单次取样复制/合成',
 '6318_ps':'颜色有效数检查，异常值归零', '6329_ps':'深度线性化和有符号离焦半径编码',
 '6343_ps':'4 色 + 4 离焦半径采样，预滤波/下采样',
 '6354_ps':'71 点圆盘采样循环，前/后景权重归一化；景深型模糊',
 '6365_ps':'四点模糊', '6378_ps':'原色/模糊色按离焦半径合成',
 '6388_ps':'曝光乘数与暗角，含模式分支',
 '6400_ps':'颜色边缘检测，无边缘 discard',
 '6411_ps':'边缘方向搜索循环 + 两张查找表，形态抗锯齿权重',
 '6423_ps':'按邻边权重混合颜色',
 '6434_ps':'在颜色空间转换间加入约 1/255 噪声抖动',
 '6448_vs':'覆盖层顶点与裁剪参数变换；不分析 UI 业务',
 '6448_ps':'覆盖层纹理/颜色/裁剪', '6460_ps':'覆盖层纹理/颜色/裁剪变体',
 '6473_vs':'文字/覆盖层顶点与距离场参数变换；不分析 UI 业务',
 '6473_ps':'文字/覆盖层纹理着色；不分析 UI 业务',
 '6497_ps':'覆盖层纹理乘色', '6642_ps':'最终单纹理复制'}

shaders=[]
for s in core['unique_shaders']:
    if s['stage']!='cs':continue
    r=dict(s)
    r['timing']=timing(s['events']);r['note']=s['label'];shaders.append(r)
for h,s in g['shaders'].items():
    a=Path(s['disassembly']['path']).read_text('utf-8')
    ops=collections.Counter(re.findall(r'^\s*\d+:\s+(\S+)',a,re.M))
    tmp=re.search(r'dcl_temps (\d+)',a)
    ids=[e['event'] for e in g['events'] if e['stages'].get(s['stage'])==h]
    loads=sum(v for k,v in ops.items() if k.startswith('ld'))
    samples=sum(v for k,v in ops.items() if k.startswith('sample'))
    key='%d_%s'%(s['first_event'],s['stage'])
    note=notes.get(key)
    if note is None:
        note=('顶点属性/矩阵变换，输出插值参数' if s['stage']=='vs' and not loads else '无循环的定长着色路径')
    shaders.append(dict(stage=s['stage'],events=ids,label=key,bytecode=s['bytecode'],disassembly=s['disassembly'],
                        static_instructions=sum(ops.values()),virtual_vector_temps=int(tmp[1]) if tmp else 0,
                        global_load_sites=loads,sample_sites=samples,loops=ops['loop'],note=note,
                        timing=timing(ids),bindings=s['bindings'],opcode_histogram=dict(ops)))

groups={
 'water_12_dispatches':[1484,1490,1495,1500,1505,1510,1515,1520,1525,1530,1537,1543],
 'ground_2_dispatches':[1472,1478],
 'all_compute':[e['event'] for e in manifests['selected_v1']['events'] if 'cs' in e['stages']],
 'height_field_light':[3867], 'volumetric_scattering':[6275], 'foam_update':[1550],
 'foam_cull':[1634], 'foam_main_draw':[6196], 'dof_disk':[6354], 'aa_weights':[6411]}
for label,eid in [('sand_main',5006),('water_main',6083),('constant_ps_depth_draws',1677),('sand_aux_color_height',2689)]:
    h=next(e for e in g['events'] if e['event']==eid)['stages']['ps']
    groups[label]=[e['event'] for e in g['events'] if e['stages'].get('ps')==h]
summary=dict(inputs={k:identity(BASE/k/'manifest.json') for k in manifests},script=identity(Path(__file__)),
             counts=dict(compute_shaders=19,graphics_shaders=len(g['shaders']),all_unique=len(shaders),
                         draws=len(g['events']),dispatches=37,counter_rows_per_run=[len(r) for r in runs]),
             groups={k:dict(events=ids,**timing(ids)) for k,ids in groups.items()},shaders=shaders,
             limitations=['All timings are local RenderDoc D3D12 instrumented replay, not live-game utilization.',
                          'Graphics timing belongs to whole draw(s), not isolated VS or PS. Do not add both stage totals.',
                          'Static instructions and virtual temporaries are not GPU ISA/physical registers.',
                          'Semantic notes outside named package mappings are instruction-based descriptions, not original HLSL identifiers.'])
(OUT/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
lines=['# test1 全帧逐 shader 索引','',
       '来源及置信边界见[执行结构分析](../../../Shader执行结构与MUSCL对照.md)。覆盖 37 次 compute、1509 条绘制 action；按原始 DXBC SHA256 去重为 19 CS、39 VS、52 PS，共 110 个程序。没有 GS/HS/DS。',
       '', 'I=静态 DXBC 指令数；R=虚拟 float4 临时槽；L=全局 load 指令位置；S=纹理采样位置；循环=静态 loop 位置。分支和动态循环改变实际执行次数，以上都不是显存事务或最终 GPU 指令数。',
       '', '时间为三次本机重放的中位数。CS 按该核出现的全部 dispatch 累加；VS/PS 按使用该程序的整条 draw 累加，包含其他阶段与固定管线。**同一次 draw 会同时出现在 VS 行和 PS 行，不能把本表时间相加。** 单次与累计也不能混比。',
       '', '机器数据包含每行完整 SHA256、所有事件号、输入资源和三次时间，见[summary.json](summary.json)。程序名未从包内匹配的条目使用描述名；UI、植被和其他物体仅列静态绘制结构，不分析业务。','']
for stage,title in [('cs','Compute：19 个核'),('vs','Vertex：39 个程序'),('ps','Pixel：52 个程序')]:
    lines.extend(['## '+title,'','| 首次事件 / 字节码 | 次数 | I / R / L / S / 循环 | 累计 ms | 写法 / 边界 |','|---|---:|---|---:|---|'])
    for s in shaders:
        if s['stage']!=stage:continue
        eid=s['events'][0]
        rel=Path(s['disassembly']['path']).relative_to(BASE).as_posix()
        lines.append('| [E%d %s](../%s) | %d | %d / %d / %d / %d / %d | %.4f | %s |'%(eid,stage.upper(),rel,len(s['events']),s['static_instructions'],s['virtual_vector_temps'],s['global_load_sites'],s['sample_sites'],s['loops'],s['timing']['median_ms'],s['note']))
    lines.append('')
(OUT/'shader_index.md').write_text('\n'.join(lines),encoding='utf-8')
print(json.dumps(summary['counts']))
for k,v in summary['groups'].items(): print(k,len(v['events']),round(v['median_ms'],6))
