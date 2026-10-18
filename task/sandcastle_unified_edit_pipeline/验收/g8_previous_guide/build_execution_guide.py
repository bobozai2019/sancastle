"""Build the offline execution guide from local source anchors; stdlib only.

Run: python -X utf8 tools/docs/build_execution_guide.py [--check]
This reads runtime code and writes documentation only. No Godot process starts.
"""
from __future__ import annotations
import argparse
import hashlib
import html
import json
import re
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/project-execution-guide.html'
INDEX = ROOT / 'docs/project-execution-guide.sources.json'
BASE = 'scripts/simulation/edit_validation/frame_pipeline/'
ENTRY = 'scripts/beach/async_pipeline_entry.gd'
REFS = {}
FILES = {}


def esc(value):
    return html.escape(str(value), quote=True)


def ref(key, path, symbol=None):
    content = (ROOT / path).read_text(encoding='utf-8-sig')
    lines = content.splitlines()
    line = 1
    if symbol:
        match = re.search(r'^(?:static )?func ' + re.escape(symbol) + r'\(', content, re.M)
        if not match:
            raise ValueError(f'Missing anchor: {path}::{symbol}')
        line = content[:match.start()].count('\n') + 1
    FILES[path] = hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
    REFS[key] = {'path': path, 'symbol': symbol or path.rsplit('/', 1)[-1], 'line': line,
                 'sha256': FILES[path], 'excerpt': '\n'.join(f'{i+1:>4}  {lines[i]}' for i in range(max(0, line-2), min(len(lines), line+11)))}
    return key


for key, path, symbol in [
    ('scene', 'scenes/main.tscn', None), ('project', 'project.godot', None),
    ('ready', ENTRY, '_ready'), ('setup', ENTRY, '_render_setup'),
    ('mark_ready', ENTRY, '_async_mark_ready'), ('process', ENTRY, '_process'),
    ('physics', ENTRY, '_physics_process'), ('configure', ENTRY, '_configure_scene'),
    ('legacy_in', ENTRY, '_async_enter_legacy'), ('legacy_out', ENTRY, '_async_leave_legacy'),
    ('capture', ENTRY, 'capture_async_checkpoint_data'), ('save', ENTRY, 'save_gpu_checkpoint'),
    ('restore', ENTRY, 'restore_gpu_checkpoint_data'), ('commit', ENTRY, '_render_async_restore_commit'),
    ('shutdown', ENTRY, 'shutdown'), ('release', ENTRY, '_render_release'),
    ('api', ENTRY, 'apply_gpu_command'), ('root_fail', ENTRY, '_fail'),
    ('controller_init', BASE+'async_controller.gd', 'initialize_render'),
    ('poll', BASE+'async_controller.gd', 'poll'), ('pump', BASE+'async_controller.gd', 'pump'),
    ('edit_submit', BASE+'async_controller.gd', '_submit_edit'),
    ('tool_submit', BASE+'async_controller.gd', '_submit_tool'),
    ('tool_record', BASE+'async_tools.gd', '_record'),
    ('tool_queue', ENTRY, '_async_queue_control'),
    ('shape_begin', ENTRY, 'begin_shape_stroke'), ('shape_end', ENTRY, 'end_shape_stroke'),
    ('smooth_gpu', BASE+'async_smooth.glsl', None),
    ('water_submit', BASE+'async_controller.gd', '_submit_water'),
    ('book', BASE+'async_controller.gd', '_book_submission'),
    ('fault', BASE+'async_controller.gd', '_fail_pipeline'),
    ('bridge', BASE+'async_controller.gd', 'bridge'),
    ('scheduler', BASE+'async_scheduler.gd', 'submit'),
    ('slots', BASE+'async_slots.gd', 'acquire'), ('slot_done', BASE+'async_slots.gd', 'completed'),
    ('transport', BASE+'async_transport.gd', 'submit'), ('retire', BASE+'async_transport.gd', 'retire'),
    ('edit', BASE+'async_editor.gd', '_record_async'), ('water', BASE+'async_water.gd', '_record'),
    ('coupled', BASE+'async_coupled.gd', 'record'), ('visuals', BASE+'async_visuals.gd', 'record'),
    ('height_pump', BASE+'async_collision.gd', 'pump'),
    ('height_pack', BASE+'async_collision.gd', '_capture_render'),
    ('height_receive', BASE+'async_collision.gd', '_receive'),
    ('height_apply', BASE+'async_collision.gd', 'physics_consume'),
    ('capture_fields', BASE+'async_checkpoint_capture.gd', '_render_capture'),
    ('candidate', BASE+'async_restore_bundle.gd', 'build_async'),
    ('codec', BASE+'async_checkpoint_codec.gd', 'validate_native'),
    ('save_file', BASE+'async_checkpoint_codec.gd', 'save'),
    ('migration', BASE+'async_legacy_migration.gd', 'convert'),
    ('terminal', BASE+'async_terminal_guard.gd', 'begin'),
    ('scene_switch', 'scripts/beach/beach_scene_service.gd', '_switch'),
    ('dispose', 'scripts/beach/beach_scene_service.gd', '_dispose_scene'),
    ('input', 'scripts/beach/beach_interaction_entry.gd', '_unhandled_input'),
    ('ray', 'scripts/beach/beach_interaction_entry.gd', 'pick'),
    ('cpu_patch', 'scripts/simulation/brushes/brush_material_coupler.gd', 'reconcile_external_sand_patch'),
    ('base_ready', 'tests/visual_water_alignment/prototypes/reference_preview.gd', '_ready'),
    ('cfl', BASE+'async_cfl_decide.glsl', None), ('seal', BASE+'async_seal.glsl', None),
    ('wire', BASE+'async_protocol.gd', None),
]:
    ref(key, path, symbol)
for path in ['scenes/playable/test1_capture.tscn', 'scenes/playable/test1_backwash.tscn',
             'scripts/simulation/edit_validation/frame_pipeline/async_select.glsl',
             'scripts/simulation/edit_validation/frame_pipeline/async_capture.glsl',
             BASE+'async_tool_select.glsl', BASE+'async_tool_capture.glsl',
             BASE+'async_gravel_normalize.glsl',
             'assets/water_material_natural_candidate/async_clock_variants_v1.json',
             'assets/test1_beach/test1_beach_release.json']:
    FILES[path] = hashlib.sha256((ROOT/path).read_bytes()).hexdigest()


def wrap(text, units):
    result, current, count = [], '', 0
    for char in str(text):
        cost = 2 if unicodedata.east_asian_width(char) in 'WF' else 1
        if char == '\n' or count + cost > units:
            result.append(current); current = ''; count = 0
        if char != '\n':
            current += char; count += cost
    if current:
        result.append(current)
    return result


def svgtext(x, y, text, units=38, cls='body', anchor='middle', step=21):
    return '<text x="%s" y="%s" class="%s" text-anchor="%s">%s</text>' % (
        x, y, cls, anchor, ''.join(f'<tspan x="{x}" dy="{0 if i==0 else step}">{esc(s)}</tspan>' for i,s in enumerate(wrap(text,units))))


DIAGRAMS = []


def frame(identifier, title, svg, width, height, description):
    DIAGRAMS.append({'id': identifier, 'title': title, 'width': width, 'height': height})
    return f'''<figure class="diagram" id="{identifier}"><figcaption><strong>{esc(title)}</strong>
    <span class="diagram-actions"><button data-zoom="out" aria-label="缩小图表">−</button><output>100%</output><button data-zoom="in" aria-label="放大图表">＋</button><button data-zoom="fit">适应宽度</button><button data-zoom="reset">原尺寸</button><button data-export>导出 SVG</button></span></figcaption>
    <p class="diagram-desc">{esc(description)}</p><div class="diagram-scroll"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}" role="img" aria-labelledby="{identifier}-title {identifier}-desc" data-native="{width}"><title id="{identifier}-title">{esc(title)}</title><desc id="{identifier}-desc">{esc(description)}</desc><defs><marker id="{identifier}-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10Z" fill="context-stroke"/></marker></defs>{svg}</svg></div></figure>'''


def flow(identifier, title, nodes, edges, description):
    """Nodes: id,column,row,title,body,owner,source. Edges: a,b,label[,style]."""
    width=1170; node_w=310; node_h=116; col_x=[30,430,830]; row_gap=182
    pos={n[0]:(col_x[n[1]],48+n[2]*row_gap) for n in nodes}
    height=max(y for x,y in pos.values())+node_h+48
    svg=''
    for edge in edges:
        a,b,label,*style=edge; kind=style[0] if style else ''
        x,y=pos[a];xx,yy=pos[b]
        if x==xx:
            start=(x+node_w/2,y+node_h);end=(xx+node_w/2,yy)
            path=f'M{start[0]} {start[1]}V{end[1]}'
            lx=start[0]+12;ly=(start[1]+end[1])/2+5;anchor='start'
        elif y==yy:
            start=(x+node_w if x<xx else x,y+node_h/2)
            end=(xx if x<xx else xx+node_w,yy+node_h/2)
            path=f'M{start[0]} {start[1]}H{end[0]}'
            lx=(start[0]+end[0])/2;ly=start[1]-10;anchor='middle'
        else:
            start=(x+node_w/2,y+node_h);end=(xx+node_w/2,yy)
            mid=y+node_h+33
            obstructed=any(nx==xx and y<ny<yy for nx,ny in pos.values())
            if obstructed:
                corridor=xx+node_w+35
                path=f'M{start[0]} {start[1]}V{mid}H{corridor}V{yy+node_h/2}H{xx+node_w}'
                lx=corridor+8;ly=(mid+yy)/2;anchor='start'
            else:
                path=f'M{start[0]} {start[1]}V{mid}H{end[0]}V{end[1]}'
                lx=(start[0]+end[0])/2;ly=mid-8;anchor='middle'
        svg+=f'<path class="edge {kind}" d="{path}" marker-end="url(#{identifier}-arrow)"/>'
        if label:svg+=svgtext(lx,ly,label,20,'edge-label',anchor,17)
    for key,col,row,heading,body,owner,source in nodes:
        x,y=pos[key]
        data=f' data-ref="{source}" role="button" tabindex="0" aria-label="{esc(heading)}，查看源码定位"' if source else ''
        svg+=f'<g class="node {owner}"{data}><rect x="{x}" y="{y}" width="{node_w}" height="{node_h}" rx="10"/>'
        svg+=svgtext(x+node_w/2,y+27,heading,36,'node-title')
        svg+=svgtext(x+node_w/2,y+53,body,38,'body')
        if source:svg+=svgtext(x+node_w-12,y+node_h-10,'↗ 源码',10,'source-tag','end')
        svg+='</g>'
    return frame(identifier,title,svg,width,height,description)


def sequence(identifier,title,lanes,events,description):
    """Events: from,to,label,owner,source; from=-1 creates a full-width note."""
    width=1200;gap=1120/max(1,len(lanes)-1);xs=[40+i*gap for i in range(len(lanes))]
    # Leave a proper half-lane margin, including for self messages.
    xs=[110+i*(980/max(1,len(lanes)-1)) for i in range(len(lanes))]
    height=130+len(events)*88
    svg=''
    for i,(name,kind) in enumerate(lanes):
        svg+=f'<line x1="{xs[i]}" y1="80" x2="{xs[i]}" y2="{height-25}" class="lifeline"/>'
        svg+=f'<g class="node {kind}"><rect x="{xs[i]-94}" y="20" width="188" height="58" rx="9"/>{svgtext(xs[i],43,name,23,"node-title",step=20)}</g>'
    for i,(a,b,label,kind,source) in enumerate(events):
        y=135+i*88
        if a<0:
            svg+=f'<rect x="18" y="{y-28}" width="1164" height="55" rx="6" class="sequence-note"/>{svgtext(600,y-7,label,115,"note-text",step=19)}'
            continue
        x=xs[a];xx=xs[b]
        attr=f' data-ref="{source}" tabindex="0" role="button" aria-label="{esc(label)}，查看源码"' if source else ''
        svg+=f'<g class="message {kind}"{attr}>'
        if a==b:
            svg+=f'<path d="M{x} {y}h68v24h-68" class="message-line" marker-end="url(#{identifier}-arrow)"/>'
            svg+=svgtext(x+12 if x<300 else x-8,y-10-(len(wrap(label,29))-1)*19,label,29,'message-text','start' if x<300 else 'end',19)
        else:
            svg+=f'<path d="M{x} {y}H{xx}" class="message-line" marker-end="url(#{identifier}-arrow)"/>'
            units=max(26,int(abs(xx-x)/8))
            svg+=svgtext((x+xx)/2,y-12-(len(wrap(label,units))-1)*19,label,units,'message-text',step=19)
        svg+='</g>'
    return frame(identifier,title,svg,width,height,description)


def table(headers, rows):
    return '<div class="table-scroll"><table><thead><tr>'+''.join('<th>'+esc(h)+'</th>' for h in headers)+'</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+str(v)+'</td>' for v in row)+'</tr>' for row in rows)+'</tbody></table></div>'


def source_button(key, label=None):
    return f'<button class="source-link" data-ref="{key}">{esc(label or REFS[key]["symbol"])}</button>'


SECTIONS=[]


def section(key,kicker,title,lead,body):
    SECTIONS.append({'id':key,'title':title,'kicker':kicker,'html':f'<section id="{key}" data-search><div class="eyebrow">{esc(kicker)}</div><h2>{esc(title)}</h2><p class="lead">{lead}</p>{body}</section>'})


section('map','01 / 入口与责任','先确定正在运行哪条路径',
 '本指南描述 2026-10-17 工作区中的正式 main 及两个可编辑 test1 入口。图中箭头是调用、消息或数据依赖，纵向顺序不代表实测耗时，也不证明 GPU 硬件重叠。',
 table(['对象','当前事实','责任边界'],[
 ('入口','main.tscn → test1_capture → test1_backwash（后两者依次继承）','三者共享静态场景、UI、工具和后端，scene_key决定初态及海侧水位'),
 ('正式根脚本','async_pipeline_entry → gravel → shape → recovery/interaction → 视觉适配 → reference_preview','继承链提供实现复用；不要把类继承顺序当成运行时调用时序'),
 ('运行配置','256²，0.125 m/格，32 m域；目标 tick 1/30 s','实际推进时间来自 GPU actual_dt，不保证墙钟30 tick/s'),
 ('后端','项目默认 D3D12 / Forward Plus，Jolt；参考验收1280×720','部分组件探针显式使用Mobile，不能当作项目默认'),
 ('模式','场景保存 async_pipeline_enabled=true；脚本导出默认false','显式旧模式用于对照；edit_frame_pipeline_enabled不替代新模式开关'),
 ('可信范围','Godot项目实现与源码核对','本指南不声称这些调度机制是竞品原作算法'),
 ])+ '<h3>执行域图例</h3><div class="legend"><span class="main">主线程 / CPU</span><span class="render">渲染线程 / RD录制</span><span class="gpu">GPU 有序队列</span><span class="worker">准备 worker</span><span class="physics">主线程物理阶段</span><span class="disk">文件边界</span><span class="error">拒绝 / 故障</span></div><p>RenderingServer.call_on_render_thread 负责将录制工作交给渲染线程；buffer/texture_get_data_async 的回调再以 call_deferred 交主线程记录。物理阶段仍在主线程，未启用独立物理线程。Worker 只准备不可变高度数据，不创建或修改 Jolt shape。</p>'
 +table(['模块','主要定位','任务'],[
 ('根入口',source_button('process'), '模式、初始化、低频边界、公开 API、关闭'),
 ('Controller',source_button('pump'), 'frame pump、公平水调度、3槽工作记录与完成消费'),
 ('Editor / Water',source_button('edit')+' / '+source_button('water'), 'GPU普通编辑 / 动态CFL与水沙耦合'),
 ('Collision',source_button('height_pump')+' / '+source_button('height_apply'), '双槽高度、CPU准备、每块物理应用'),
 ('Checkpoint / Candidate',source_button('capture_fields')+' / '+source_button('candidate'), '完整采集、校验、独立候选恢复'),
 ('BeachScenes',source_button('scene_switch'), '会话保存、旧场景释放、目标准备或重建回退'),
 ]))

section('boot','02 / 初始化','启动到 ready：资源先就绪，输入再开放',
 '场景、UI层级、固定资源和信号连接来自 .tscn/.tres。运行时创建的是 RD 纹理、缓冲、求解器与协调对象；没有在 _ready 中重建固定 UI。',
 flow('boot-flow','初始化流程图',[
 ('a',0,0,'加载正式入口','project.godot → main.tscn\n或继承的test1场景','main','project'),
 ('b',0,1,'建立 async 协调对象','controller / scheduler\nledger_precision=approximate','main','ready'),
 ('c',0,2,'沿继承链初始化','域初态、有效profile\n静态材质参数与SPIR-V','main','base_ready'),
 ('d',1,2,'渲染线程建立资源','原solver/工具/视觉\ntransport、水、耦合、双高度槽','render','setup'),
 ('e',1,3,'绑定完成态资源','Texture2DRD稳定发布\n1×1 GPU完成时钟','render','configure'),
 ('f',0,3,'等待bootstrap原碰撞','原staging读回/准备/pending\n全部结束后交给新碰撞所有者','main','mark_ready'),
 ('g',0,4,'开放正常运行','backend_ready/controller.ready\nready_for_ticks完成','main','mark_ready'),
 ('h',2,3,'初始化失败','锁存错误，停止准入\npartial资源仍按所有者收尾','error','root_fail'),
 ],[('a','b',''),('b','c',''),('c','d','交RD'),('d','e','成功'),('e','f','主线程'),('f','g','无旧消费者'),('d','h','失败','error')],
 '初始化成功必须同时满足原资源与新后端就绪；有效profile可能覆盖场景导出默认值，local-front是否存在以实际初始化资源为准。')
 +sequence('boot-sequence','初始化时序图', [('主线程 / 场景','main'),('继承初始化链','main'),('渲染线程','render'),('GPU / 读回','gpu')],[
 (0,1,'实例化静态场景；_ready → super','main','ready'),
 (1,1,'初始化Domain、profile、材质和shader输入','main','base_ready'),
 (1,2,'call_on_render_thread(_render_setup)','render','setup'),
 (2,3,'创建solver/工具/视觉及初始碰撞请求','gpu','setup'),
 (2,3,'创建3工作槽/2高度槽/动态水调度资源','gpu','controller_init'),
 (2,0,'defer _async_mark_ready(token)','render','mark_ready'),
 (-1,-1,'bootstrap边界：新高度所有者接手前，排空原碰撞staging、pending和worker','main',None),
 (3,0,'原生读回与CPU准备完成','gpu','mark_ready'),
 (0,0,'token匹配且无错误 → ready','main','mark_ready'),
 ],'右侧异步返回不等于原碰撞已经排空；ready门保护新旧碰撞版本交接。'))

section('frame','03 / 普通帧','每帧调度：就绪消费、有限提交、独立物理应用',
 '正常路径避免应用层等待上一批CPU验收。固定容量形成背压：槽忙时本次不提交，输入保留；已有GPU工作继续。GPU对共享scratch保持单一有序录制与执行。',
 flow('frame-flow','CPU frame pump 与物理阶段',[
 ('a',0,0,'_process(delta)','先 poll，再 pump\n随后继续 super._process','main','process'),
 ('b',0,1,'poll按batch顺序消费','仅就绪槽；更新tick/time\n元数据与名义估算只计一次','main','poll'),
 ('c',0,2,'可调度？','ready、非legacy/frozen\n非closing、无锁存错误','main','pump'),
 ('d',0,3,'安排有界工作','显式tick / 边界到期tick\n欠水优先，最多一批编辑/帧','main','pump'),
 ('e',1,3,'RD记录工作','按顺序编辑或水tick\n不等CPU逐笔回执授权','render','transport'),
 ('f',1,4,'GPU发布与seal','完整状态→完成通知/时钟\n后继工作可在CPU消费前记录','gpu','seal'),
 ('g',0,4,'安排高度快照','pending存在且高度槽可用\n槽满保留脏区','main','height_pump'),
 ('h',2,0,'_physics_process','只消费已准备结果\n不等待未完成worker','physics','physics'),
 ('i',2,1,'按块安装碰撞','同generation，版本不倒退\n未变高度可跳过替换','physics','height_apply'),
 ],[('a','b',''),('b','c',''),('c','d','允许'),('d','e','有槽'),('e','f','有序GPU'),('d','g','同帧末尾'),('h','i','worker完成')],
 'water_owed避免持续编辑饿死水tick；自动时间累积最多4个名义步。显式tick和低频边界排空是单独的受控分支。')
 +sequence('batch-sequence','连续两批：GPU完成与CPU消费分离', [('输入 / 主线程','main'),('3槽 Controller','main'),('渲染线程','render'),('GPU队列','gpu'),('物理阶段','physics')],[
 (0,1,'submit接纳命令到64笔有界队列','main','scheduler'),
 (1,2,'租槽A；取最多2笔普通输入','render','edit_submit'),
 (2,3,'上传一次；记录A的完整pass和seal','gpu','transport'),
 (0,1,'后续输入继续入队','main','scheduler'),
 (1,2,'存在空槽B → 提交B，不等A的CPU消费','render','edit_submit'),
 (2,3,'A之后有序记录B，scratch不并发写','gpu','transport'),
 (3,0,'A末80B读回回调 → defer _receive','gpu','slot_done'),
 (1,1,'后续poll更新元数据、退CPU租约','main','poll'),
 (1,2,'排队retire_render；允许后续按序复用','render','retire'),
 (3,0,'高度快照读回 → worker准备','gpu','height_receive'),
 (0,4,'独立物理阶段安装已就绪shape','physics','height_apply'),
 ],'示意允许存在的顺序，不是固定帧延迟：GPU工作有序；CPU消费和碰撞应用不承担普通下一批的发布授权。')
 +'<h3>pump 的实际提交优先级</h3><pre><code>poll：按 batch_seq 消费已经就绪的通知\npump：ready / 非 frozen / 无错误时才进入\n  1. 显式水 tick（有界请求）\n  2. 保存/恢复边界：只补足已接纳 future 命令到期所需 tick\n  3. 实时模式中，上次因满槽欠下的 water_owed\n  4. 本渲染帧尚未提交过编辑 → 普通前缀或队首工具工作\n  5. 若本帧还没提交水且自动累计到期 → 尝试 water tick\n  6. 尝试 pending 高度快照；满槽继续记脏</code></pre><p>所有 edit/tool/water 工作共用3个槽；一帧最多一次编辑或工具提交，水工作优先级用于防饥饿。工具不进入legacy，实时笔画期间水模拟继续。根入口仍调用 super._process 处理继承功能，新模式禁止基类再启动第二套自动水tick。物理消费由独立 _physics_process 阶段调用。</p>')

section('input','04 / 命令接纳','从鼠标到GPU批次：身份、模式和拒收边界',
 '所有操作进入同一有界队列。schema-v1的床面/悬沙挖填可取同策略批次；形状、平滑、压实和碎石作为独立工具工作，共享相同槽、GPU顺序与碰撞发布机制。',
 flow('input-flow','输入与分流流程图',[
 ('a',0,0,'鼠标 / UI / 相机过滤','UI遮挡、右键视角、关闭\n未ready时不进入世界编辑','main','input'),
 ('b',0,1,'Jolt射线与笔段采样','使用已有完整碰撞面\ncircle或swept_segment','main','ray'),
 ('c',0,2,'构造命令与选择快照','domain/generation/command_id\nsim_tick、体积、policy/speed','main','scheduler'),
 ('d',0,3,'scheduler.submit','有限值与合法性验证\n队列64、准入/代次保护','main','scheduler'),
 ('e',1,3,'拒收或边界繁忙','queue_full / invalid_input\n松开仍结束；拒收间隙不补画','error','scheduler'),
 ('f',0,4,'床面 / 悬沙编辑','按due tick、同policy取前缀\n默认2笔，每帧至多一次提交','main','edit_submit'),
 ('g',1,4,'形状 / 其他工具','队首工具工作，共享3槽\n不暂停、不读CPU影子、不bridge','main','tool_submit'),
 ('h',0,5,'GPU自行决定每笔','验证后提交或跳过\n不回到CPU逐笔授权','gpu','edit'),
 ],[('a','b','有效输入'),('b','c','命中'),('c','d',''),('d','e','拒收','error'),('d','f','普通且接纳'),('d','g','其他类型'),('f','h','有槽/到期')],
 '停止准入不等于资源已空闲；command_id允许拒收留下空隙，不能为了补齐编号补画轨迹。')
 +table(['标识','表示什么','不能用来替代什么'],[
 ('domain_id','场景域身份','不能只凭同一场景名跨域恢复'),
 ('generation','场景/恢复代次','旧回调不能回写新场景'),
 ('command_id','已接纳命令顺序，高水位单调','不是成功笔数，拒绝也不重用身份'),
 ('batch_seq + slot_id + lease_id','工作单元与当前槽租约','slot_id单独不能证明当前所有权'),
 ('state_seq','GPU seal后的完整工作序号','不等于sim_tick或revision'),
 ('sim_tick / revision','水tick计数 / 求解器修订','不能当作每块碰撞已追平的证明'),
 ('snapshot_seq','不可变高度请求身份','不是全场统一物理版本'),
 ]))

section('gpu-edit','05 / GPU 编辑','候选先验证，成功才写权威场',
 '一次批量上传保留笔段顺序，不把多笔体积融合成一次求解。A成功、B拒绝、C成功时，B不污染权威状态，C读取A完成后的真实GPU控制状态继续执行。',
 flow('edit-flow','每批内部的GPU编辑流程',[
 ('a',0,0,'Transport 上传并记录','64B header + 128B×命令\n按租约使用持久input缓冲','render','transport'),
 ('b',0,1,'每笔 async_select','从GPU control取当前版本\n生成间接组数和本笔身份','gpu','edit'),
 ('c',0,2,'计算候选','沙分配/水响应/材料候选\n共享scratch只供有序工作使用','gpu','edit'),
 ('d',0,3,'完成所有有效性验证','沙、水、动量、悬沙、支撑等\n验证发生在权威提交之前','gpu','edit'),
 ('e',1,3,'正常拒绝：跳过本笔','不写权威沙水材料\n更新拒绝诊断，继续下一笔','error','edit'),
 ('f',0,4,'统一提交本笔结果','commit及extra_commit\n更新GPU控制与本笔诊断','gpu','edit'),
 ('g',0,5,'整批末完整发布','publish_sand → transport seal\n更新state_seq和GPU完成时钟','gpu','seal'),
 ('h',1,5,'异步80B完成通知','身份/协议/有限值/标志验证\n不是CPU逐笔质量验收','main','slot_done'),
 ],[('a','b',''),('b','c',''),('c','d',''),('d','e','拒绝','error'),('d','f','通过'),('f','g','处理其余笔'),('e','g','其余笔继续'),('g','h','GPU末端读回')],
 '图中“处理其余笔”代表回到select的批内循环。床面/悬沙路径没有每批14张临时全场备份；形状工具也在GPU完成候选验证后提交，CPU回执不授权下一段。')
 +'<h3>账本与公开接口</h3><p>普通自由编辑按已记录提交的名义体积×strength更新近似源汇，只计一次；正常GPU拒绝也可能保留名义估算，不能以严格闭合误差阻止普通发布。提交前明确失败不记该名义量。'+source_button('book')+'。公开 '+source_button('api')+' 是等待自身 command_id/generation 终端结果的便捷协程；普通UI只入队，不逐笔await。真实故障/关闭/换代返回明确错误，不等待实时管线全局idle，也不伪造成功。</p>')

section('water','06 / 水沙 Tick','GPU决定子步，全部关联阶段消费同一实际时间',
 'CPU为一个名义1/30秒tick记录有界的64段间接工作。GPU决定有效N和actual_dt；未使用的子步组数为0。边界写入前先做安全CFL判断，边界后再次归约，整个过程不离开GPU序列。',
 flow('water-flow','一个水tick的完整GPU阶段',[
 ('a',0,0,'初次 CFL tiles / decide','读取当前水深与动量\n保护非有限输入，生成决策','gpu','water'),
 ('b',0,1,'海侧边界与波包','按GPU实际时间采样\n写潮汐/波浪及水源汇','gpu','water'),
 ('c',0,2,'再次 CFL 归约 / decide','边界可能改变波速\n重算安全N、dt、actual_dt','gpu','cfl'),
 ('d',0,3,'每个有效子步','共享边通量 → drain_scale\n→ water/momentum update','gpu','water'),
 ('e',1,3,'子步耦合阶段','悬沙搬运/侵蚀沉积\n支撑、湿度压实、坡面、提交','gpu','coupled'),
 ('f',0,4,'归一权威槽为0','水、动量、沙、悬沙、flux等\n奇偶N不交给CPU判槽','gpu','water'),
 ('g',0,5,'sim_finish与视觉尾部','更新tick/actual时间\nlocal-front → foam → gravel','gpu','visuals'),
 ('h',1,5,'视觉归一、发布与seal','完整发布沙水/显示纹理\n1×1时钟及80B完成信息','gpu','seal'),
 ],[('a','b','合法'),('b','c',''),('c','d','N=1…64'),('d','e','每子步'),('e','f','所有子步后'),('d','f','耦合关闭'),('f','g',''),('g','h','')],
 '所有细分阶段通过RD可见性/序列依赖访问当前状态。CFL非法时设置错误并阻止后续权威/视觉写入；不是自动退回固定子步。')
 +'<div class="formula"><strong>GPU决策</strong><code>safe_dt = courant × cell_size / max_speed<br>N = clamp(ceil(requested_dt / safe_dt), 1, 64)<br>actual_dt = min(requested_dt, 64 × safe_dt)<br>substep_dt = actual_dt / N</code></div><p>超过64子步需求时缩短实际推进时间；不能把tick数/30当作真实表现时间。侵蚀/沉积的小步比例保持1−exp(−rate×dt)语义，使用小量稳定展开避免float32相消。local-front读取当前水沙及上一泡沫/床面，然后更新泡沫；碎石只读权威水沙，使用本tick实际dt并归一自己的历史。</p>'
 +table(['资源/时钟','写入位置','使用者'],[
 ('GPU control / decision','CFL、sim_finish、seal','后继GPU工作、异步CPU完成镜像'),
 ('1×1 R32F completed_clock','seal','async水/沙静态派生shader；暂停保持完成时间'),
 ('稳定发布纹理 / Texture2DRD','完整工作边界','沙面、水面、相关显示层；不等CPU账本授权'),
 ('CPU shadow','保留旧模式和初始化/恢复容器；默认工具不请求同步','不是编辑、形状或水tick的逐笔准入条件'),
 ]))

section('collision','07 / 异步碰撞','实际床面快照：GPU继续写，CPU之后装形状',
 'pending表示尚需采集的脏块，in-flight表示已拍下的不可变快照。两者必须分开：同块新修改不能因旧请求在途而丢失；不同块也不能互相覆盖。',
 sequence('height-sequence','高度快照到Jolt的时序图',[('Controller / 主线程','main'),('渲染线程','render'),('GPU','gpu'),('Prepare worker','worker'),('物理阶段 / 主线程','physics')],[
 (0,0,'普通笔段保守记脏；侵蚀水tick mark_all','main','height_pump'),
 (0,1,'空高度槽：从pending取最多16块','render','height_pump'),
 (1,2,'同次pack读取control标签与rock+sand','gpu','height_pack'),
 (-1,-1,'快照槽固定2个；槽满仍保留pending，普通GPU写入继续；每块33×33样本含共享边','main',None),
 (2,0,'不可变快照异步读回，检查身份/大小/有限值','gpu','height_receive'),
 (0,3,'WorkerThreadPool.add_task(prepare_serial)','worker','height_receive'),
 (3,4,'准备完成后才消费；未完成则本次跳过','worker','height_apply'),
 (4,4,'按generation + 每块state_seq过滤旧数据','physics','height_apply'),
 (4,4,'安装shape；相同高度底层可跳过替换','physics','height_apply'),
 (4,0,'记录applied_state_seq/sim_tick并释放CPU槽','physics','height_apply'),
 ],'GPU读回结束释放其快照缓冲所有权；CPU槽还需等worker与物理消费结束。RD槽和CPU槽的最后消费者不是同一个时点。')
 +table(['情形','处理','验证含义'],[
 ('槽满','保留pending，之后重新拍最新高度','不得封锁所有GPU写入'),
 ('普通拒绝笔','仍按保守范围请求高度','不假设拒绝代表无需刷新'),
 ('同块旧结果晚到','按每块state_seq过滤','不能用单一全场watermark覆盖所有块'),
 ('坏长度/NaN/旧代次','不污染shape；适用时重记脏','保留上一份合法碰撞'),
 ('停手收尾','停止输入及自动地形改变，排空pending和in-flight','最终逐点等于当前GPU rock+sand；不承诺固定落后帧数'),
 ]))

section('tools','08 / 全工具流水线','形状、平滑、压实和碎石共用有序GPU工作流',
 '沙墙、城堡、守恒铲子、平滑/压实和投碎石以独立工具信封提交；投流沙已并入普通编辑批次。工具与水tick共享3个工作槽，不暂停整笔画墙期间的水模拟。',
 sequence('tool-sequence','新工具时序图',[('工具 / UI','main'),('队列 / Controller','main'),('持久工作槽','main'),('渲染线程 / GPU','gpu'),('异步碰撞','worker')],[
 (0,1,'begin / 段 / end，或平滑/压实/碎石命令','main','tool_queue'),
 (1,2,'按队首顺序取得共享槽；满槽有界背压','main','tool_submit'),
 (2,3,'256B工具信封；显式扩展版本/stride','gpu','tool_record'),
 (3,3,'GPU填写实际revision/tick及笔画身份','gpu','tool_record'),
 (3,3,'复用几何/守恒候选，或GPU平滑/压实候选','gpu','smooth_gpu'),
 (3,3,'全部检查完成后提交权威；复制本槽回执','gpu','tool_record'),
 (3,0,'完整发布；不等CPU授权即可录制后续工具/水tick','gpu','tool_record'),
 (3,2,'同次有序读回80B完成通知+256B回执','gpu','transport'),
 (1,1,'验证身份/revision/tick，记录自身终端结果','main','poll'),
 (1,4,'GPU实际高度快照，物理阶段追赶碰撞','worker','height_apply'),
 (0,1,'end结束GPU基准；保存/切换/退出再排空','main','shape_end'),
 ],'公开API允许等待自身结果，下一段GPU工作不依赖CPU逐段回执或碰撞。取消清未接纳采样，已接纳段继续结算。')
 +'<p>形状基准/coverage按笔画保留；铲子按原采样段分配实际挖出量，不按忙闲改成长段。平滑在GPU使用加权目标和校正，并协调材料tag/reference双槽；与旧CPU double实现按float32误差及守恒边界验证。压实写R16F；碎石只改表现状态，允许多个投放在通知前接纳。细节见 <a href="当前项目技术方案.md#55-全工具接入新流水线2026-10-17">全工具迁移</a>。</p>')

section('checkpoint','09 / 保存与恢复','完整状态快照和独立候选：不用逐笔重放',
 '保存读取完整完成态；恢复先验证私有输入，再创建独立资源候选，确认原生数据后发布。提交前失败保留旧状态；发布后致命错误停止新所有者，不能声称已回滚。',
 sequence('save-sequence','保存时序图',[('调用者','main'),('async根 / Controller','main'),('渲染线程 / GPU','gpu'),('Capture所有者','main'),('文件系统','disk')],[
 (0,1,'save_gpu_checkpoint(path)','main','save'),
 (1,1,'关闭新准入/自动tick，取消未入队UI点','main','capture'),
 (1,1,'排空已接纳普通/受控工具；必要时推进future due tick','main','capture'),
 (1,1,'transitioning + frozen；固定完成边界','main','capture'),
 (1,3,'注册独立Capture所有者','main','capture_fields'),
 (3,2,'读取全部原生双槽/材料/历史/碎石/control','gpu','capture_fields'),
 (2,3,'每份异步回调按key收齐并核对尺寸','gpu','capture_fields'),
 (3,3,'严格校验、完整性确认；失败不产出成功文件','main','codec'),
 (3,1,'返回不可变RAM快照；健康时恢复原准入','main','capture'),
 (1,4,'create-only临时文件→flush→rename，magic与checksum','disk','save_file'),
 (4,0,'成功或明确错误；既有文件不覆盖','disk','save_file'),
 ],'普通保存不以逐笔碰撞ACK为前提；采集期间权威写入被冻结。部分读回注册失败仍须等已注册消费者和终结证明，不能用空数组补齐。')
 +flow('restore-flow','候选恢复与失败分支',[
 ('a',0,0,'识别容器及版本','SANDGP05或受支持SANDCP01\n旧格式完整验证后显式迁移','main','migration'),
 ('b',0,1,'私有输入完整验证','checksum/大小/有限值/配置\ndomain、源码资源及引擎身份','main','restore'),
 ('c',0,2,'关闭准入并排空消费者','结束UI笔画/工具工作/碰撞\npreview与采样消费者','main','restore'),
 ('d',0,3,'建立独立候选','新generation；完整原生字段\n候选solver/controller/工具/视觉','render','candidate'),
 ('e',0,4,'候选31份读回比较','当前/备用、材料、历史\n碎石、发布场、时钟和control','main','candidate'),
 ('f',1,4,'提交前失败','证明候选终结后丢弃\n旧身份和活跃资源保持','error','restore'),
 ('g',0,5,'提交并重绑资源','提交元数据→渲染线程发布\n旧资源按依赖释放','render','commit'),
 ('h',0,6,'重建全64块碰撞','mark_all并等完整应用\n刷新profile/选择，恢复准入','main','restore'),
 ('i',1,6,'提交后致命错误','保留已提交新状态并停止\n明确after_restore_commit错误','error','restore'),
 ],[('a','b',''),('b','c','验证通过'),('c','d',''),('d','e',''),('e','f','失败','error'),('e','g','全部一致'),('g','h','健康'),('g','i','发布后失败','error')],
 '候选拥有自己的资源与验证回调，不能临时替换活跃root来“验证”。未确认终结时保留候选及旧资源，返回ownership_unconfirmed。')
 +table(['子记录','保存内容','适用边界'],[
 ('edit v5 / native v3','权威fields与spare、材料双槽、泡沫/床面、local-front、control','当前槽规范为0；大小/有限值/身份严格校验'),
 ('运行元数据','state_seq/tick/revision/actual_time、近似账本、选择、高水位、波请求时钟','不依赖旧prefix、撤销或逐笔重演'),
 ('visual_extensions.gravel_v1','独立碎石profile/状态双槽/active_count','表现子记录，不混入沙量'),
 ('受支持旧v4/nativev2','原Store/BeachRecovery/BrushCodec验证后投影','只迁移相容引擎/源码/资源；不伪造回执'),
 ('local-front浮点边界','保留原始RG32F字节，允许已推导的质心归约舍入上界','NaN/Inf/负值和明显越界仍拒绝；不裁剪或量化'),
 ('未覆盖开关','structures、rise_front、contact_history','明确unsupported，不能遗漏记录后假装恢复成功'),
 ]))

section('lifecycle','10 / 切换与退出','场景销毁的条件是最后消费者完成',
 'BeachScenes持有会话进度和当前场景身份。正常切换先保存、释放旧场景，再准备目标；新旧场景不并行写共享后端。文件扩展名可能仍是 .sandcp，格式识别依赖magic而不是扩展名。',
 sequence('switch-sequence','场景切换与回退时序图',[('UI / BeachScenes','main'),('旧场景','main'),('会话文件','disk'),('目标场景','main')],[
 (0,1,'阻挡重复请求、世界笔刷和相机输入','main','scene_switch'),
 (0,1,'保存旧场景完整进度','main','scene_switch'),
 (1,2,'新建会话文件；saved[old_key]登记','disk','save'),
 (0,1,'shutdown；确认gpu_release_done与各RD所有者','main','dispose'),
 (-1,-1,'旧场景释放不确认：保留旧Node与active/current_scene，停止目标加载，已保存进度保留','error',None),
 (0,1,'仅确认释放成功才queue_free旧Node','main','dispose'),
 (0,3,'实例化目标：树外传generation与async模式','main','scene_switch'),
 (3,3,'初始化；有saved则恢复对应检查点','main','restore'),
 (3,0,'成功：设置active/current并应用共享控制','main','scene_switch'),
 (-1,-1,'目标失败：丢弃失败目标，从刚保存文件重建原场景；此时不是继续使用已销毁旧Node','error',None),
 ],'保存失败直接保留原场景；旧释放失败不创建目标；目标失败才走重建回退。这三条不能合并成一个“总能无损返回”的承诺。')
 +flow('shutdown-flow','正常关闭与所有权未确认',[
 ('a',0,0,'shutdown_requested=true','幂等关闭；停止新准入\n先处理已有保存/恢复所有者','main','shutdown'),
 ('b',0,1,'终结工具与UI边界','取消未提交采样\n结束笔画并确认在途工作消费者','main','shutdown'),
 ('c',0,2,'排空新工作与两类碰撞','停批次准入，冻结controller\nworker、preview、receipt归零','main','shutdown'),
 ('d',0,3,'独立 final 有序读回','16B锚点；证明整个RD末消费者\nprobe不能代替final','render','terminal'),
 ('e',0,4,'按依赖释放','controller/绑定/时钟wrapper\n继承资源/solver最后释放','render','release'),
 ('f',0,5,'确认释放才销毁Node','gpu_release_done + RD为空\nSceneService才queue_free','main','dispose'),
 ('g',1,3,'无法证明工作结束','保留租约、RD、Node\n有界返回ownership_unconfirmed','error','shutdown'),
 ('h',1,4,'能力恢复后重试证明','仅确认原工作终结并清理\n管线仍失败，不重发命令','error','terminal'),
 ],[('a','b','无unknown'),('b','c',''),('c','d',''),('d','e','确认'),('e','f',''),('d','g','不可用','error'),('g','h','允许重试','error')],
 '工具与水/编辑共用工作租约；关闭须结束笔画、排空在途工作和实际碰撞消费者。初始化或旧模式仍可能持有原代理资源，各所有者分别确认后才释放。')
 +table(['异常分类','处理策略','禁止的替代做法'],[
 ('正常GPU命令拒绝','只跳过本笔，后续继续','不能当成设备错误整批回滚'),
 ('明确提交前失败','unrecorded_abort、回收未记录租约','不记成功或名义源汇，不伪造完成'),
 ('已记录但完成读回注册失败','停止管线；独立有序终结证明后清理','不因返回错误而重发可能已执行的命令'),
 ('坏协议/身份/时间/错误标志','不正常consume，不推进CPU成功状态','不拿终结payload修复回执'),
 ('工作/高度/捕获/候选/旧工具所有者','每个通道分别确认最后消费者','不能用新records为空证明所有资源可free'),
 ('真实驱动失效','保留明确未测试边界；本轮仅可控注入','不能把注入PASS写成真实驱动重置恢复已验'),
 ]))

section('contracts','11 / 状态与修改指导','资源、状态和常见修改入口',
 '先确定修改归属，再选择验证。改变显示不应修改权威沙水；改变协议或保存子记录时，CPU、shader、codec和探针必须同步。',
 flow('slot-flow','工作槽生命周期',[
 ('a',0,0,'FREE','固定持久资源\n没有当前租约','main','slots'),
 ('b',0,1,'CPU_FILLING','获取generation/batch/slot/lease\n准备本次不可变输入','main','slots'),
 ('c',0,2,'GPU_QUEUED','提交并保留输入/绑定\nGPU及末读回仍可能使用','render','transport'),
 ('d',0,3,'GPU_COMPLETE','可信闭包身份+有效payload\n仅通知就绪，尚未CPU消费','main','slot_done'),
 ('e',0,4,'CPU_RECLAIM → FREE','poll消费镜像，CPU租约回收\nRD retire按同序列排队','main','poll'),
 ('f',1,2,'已记录结果未知/坏通知','停止准入；不能提前退租\n请求独立终结证明','error','fault'),
 ('g',1,3,'证明成功 → error_abort','render retire确认后清CPU槽\n不走正常consume','error','fault'),
 ('h',2,3,'证明不可用','持有租约/资源/Node\n只允许继续清理证明','error','terminal'),
 ],[('a','b','acquire'),('b','c','submitted'),('c','d','validated callback'),('d','e','poll'),('c','f','故障','error'),('f','g','终结确认','error'),('f','h','不可用','error')],
 'CPU槽FREE和RD transport租约退役是两个对象的状态；其操作在渲染序列中保持顺序。实际释放仍同时核对records、CPU槽和transport所有权。')
 +table(['固定容量','当前值','扩展时要核对'],[
 ('命令队列 / 默认批量 / 最大批量','64 / 2 / 64','拒收断笔、同policy前缀、UI release处理'),
 ('工作槽 / 高度槽','3 / 2','槽租约与GPU/CPU最后消费者；不按负载扩容'),
 ('单高度快照','最多16块，每块33²；全场64块','共享边、停手最终收敛、pending与in-flight分离'),
 ('wire','64B header；普通128B/80B，工具256B/336B；control 128B','工具头声明扩展版本/stride；uint64用两个u32，不放进float32'),
 ('water decision / indirect','64B / 64×12B','N奇偶、N64、超限actual_dt及非法值保护'),
 ('波包 / 诊断历史','128个vec4 / 常用环形记录128条','高水位与活跃波时钟，不让历史无限增长'),
 ])+table(['要修改的功能','先读源码入口','至少验证'],[
 ('普通工具/分批策略',source_button('scheduler')+' '+source_button('edit_submit'), '接纳/拒收、同policy、顺序、槽满、后续水tick'),
 ('候选写点/水响应',source_button('edit'), '干湿/材料真实拒绝下全部权威字段不变'),
 ('CFL/耦合步长',source_button('water')+' '+source_button('coupled'), 'N1/2/3/64、超限、非法、时钟与关联视觉'),
 ('碰撞',source_button('height_pack')+' '+source_button('height_apply'), '跨块/共享边、乱序、坏数据、实际射线、收尾'),
 ('保存字段/迁移',source_button('codec')+' '+source_button('candidate'), '双槽/历史/控制逐项恢复，坏候选保持旧态'),
 ('工具工作',source_button('tool_submit')+' '+source_button('tool_record'), '基准/coverage、守恒、无CPU授权继续、在途保存/退出'),
 ('资源/关闭',source_button('shutdown')+' '+source_button('terminal'), '各所有者partial/unknown、不可确认不free、不重发'),
 ])+'<p class="callout">代码中仍有开发期“candidate/main待切换”等注释；正式接线以场景保存值、实际profile和G7证据为准。旧性能FAIL、母任务暂停与早期精确前缀结果保持各自历史范围。</p>')

section('evidence','12 / 验证与来源','如何复验、如何更新这份指南',
 '指南由源码锚点静态生成；全工具迁移的实际运行结果单独记录，不把文档构建或预览计作GPU验收。前一阶段G7保持原范围。',
 table(['证据','结果与范围','入口'],[
 ('全工具迁移','七类旧操作接入同一流水线；本轮三入口/边界/故障验证单独记录','<a href="../task/sandcastle_all_tools_pipeline/执行状态.md">本轮状态与证据</a>'),
 ('G7交付','32/32；V01–V16映射；13次1889项核对','<a href="../task/sandcastle_gpu_pipeline/验收/G7_功能交付.md">交付报告</a>'),
 ('最终源码','7次1316项；相邻未受codec修改组件6次573项','<a href="../test_output/gpu_pipeline/g7_20261017_03/g7_final_manifest.json">本机manifest（ignored机器产物）</a>'),
 ('联合连续操作','10轮完整保存/恢复/切换，实际混合180455ms','<a href="../test_output/gpu_pipeline/g7_20261017_03/delivery_10_cycles.json">本机连续结果</a>'),
 ('稳定版本契约','C01–C07及P07材料/浮点边界修订','<a href="../task/sandcastle_gpu_pipeline/接口与状态契约.md">接口与状态契约</a>'),
 ('项目说明','当前技术、操作、场景复用','<a href="当前项目技术方案.md">技术方案</a> · <a href="主场景操作.md">操作</a> · <a href="场景切换与功能复用.md">场景切换</a>'),
 ])+ '<h3>推荐回归入口</h3><p>协议/资源 → 普通编辑 → 动态水/碰撞 → 三入口工具/UI → 保存恢复/迁移/各所有者故障 → 最后集中十轮连续验证。只重跑受影响范围；不要机械重复旧性能专项。</p><pre><code>tests/integration/async_pipeline_contract_probe.gd\ntests/integration/async_pipeline_edit_probe.gd\ntests/integration/async_pipeline_water_probe.gd\ntests/integration/async_pipeline_collision_probe.gd\ntests/integration/async_pipeline_main_probe.gd\ntests/integration/async_pipeline_restore_probe.gd\ntests/integration/async_pipeline_migration_probe.gd\ntests/integration/async_pipeline_delivery_probe.gd</code></pre><h3>本指南维护</h3><pre><code>python -X utf8 tools/docs/build_execution_guide.py\npython -X utf8 tools/docs/build_execution_guide.py --check</code></pre><p>生成器读取本地方法锚点，输出HTML与来源索引；锚点不存在时明确失败。修改源码后须重新核对流程语义，hash更新不等于新实现已验收。来源索引 <a href="project-execution-guide.sources.json">project-execution-guide.sources.json</a> 与HTML都应提交，机器运行结果可能只在本机存在。HTML的流程图和时序图均为内嵌SVG，离线可读；节点/消息可用鼠标或Enter查看真实方法定位和摘录。</p>')


def build():
    template=(Path(__file__).with_name('execution_guide_template.html')).read_text(encoding='utf-8')
    sources_json=json.dumps(REFS,ensure_ascii=False).replace('</',r'<\/')
    nav=''.join(f'<a href="#{s["id"]}"><small>{s["kicker"].split(" /")[0]}</small>{s["title"]}</a>' for s in SECTIONS)
    result=template.replace('<!-- GUIDE_NAV -->',nav).replace('<!-- GUIDE_SECTIONS -->','\n'.join(s['html'] for s in SECTIONS)).replace('/* GUIDE_SOURCES */',sources_json)
    assert '<!-- GUIDE_' not in result and '/* GUIDE_SOURCES */' not in result
    # The source index is intentionally separate from prior immutable run manifests.
    manifest={'document':'project-execution-guide.html','date':'2026-10-17',
        'scope':'Godot main + editable test1 all-tools async pipeline; static source graph, runtime evidence recorded separately',
        'source_sha256':dict(sorted(FILES.items())), 'anchors':REFS,
        'generator_sha256':{p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in [Path(__file__),Path(__file__).with_name('execution_guide_template.html')]},
        'diagrams':DIAGRAMS,'sections':[{'id':s['id'],'title':s['title']} for s in SECTIONS],
        'html_sha256':hashlib.sha256(result.encode('utf-8')).hexdigest()}
    return result,json.dumps(manifest,ensure_ascii=False,indent=2)+'\n'


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    result,index=build()
    if args.check:
        assert OUT.read_text(encoding='utf-8')==result,'HTML stale; regenerate after semantic review'
        assert INDEX.read_text(encoding='utf-8')==index,'Source index stale'
    else:
        # Canonical bytes keep the embedded HTML hash valid on Windows too.
        OUT.write_text(result,encoding='utf-8',newline='\n')
        INDEX.write_text(index,encoding='utf-8',newline='\n')
    print(json.dumps({'pass':True,'mode':'check' if args.check else 'build','sections':len(SECTIONS),'diagrams':len(DIAGRAMS),'anchors':len(REFS),'source_files':len(FILES),'html_bytes':len(result.encode('utf-8'))}))


if __name__=='__main__':main()
