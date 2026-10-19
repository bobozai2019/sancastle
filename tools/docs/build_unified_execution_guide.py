"""Build the current offline guide from exact unified source anchors."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[2]
OUTPUT=ROOT/'docs/project-execution-guide.html'
INDEX=ROOT/'docs/project-execution-guide.sources.json'
BASE='scripts/simulation/unified_edit/'
ANCHORS=[('入口','scripts/beach/unified_playable_entry.gd','_ready'),
         ('声明',BASE+'player_input.gd','begin'),('注册表',BASE+'profile_registry.gd','resolve'),
         ('冻结配置',BASE+'configuration.gd','freeze'),('主调度',BASE+'pipeline.gd','pump'),
         ('唯一录制',BASE+'pipeline.gd','_submit_render'),('编辑骨架',BASE+'executor.gd','record'),
         ('公共水响应',BASE+'water_response.gd','record'),('水条件提交',BASE+'water_response.gd','commit'),
         ('排水分阶段录制',BASE+'water_response.gd','_packed_math'),('排水特化阶段',BASE+'water_response.gd','_packed_phase'),
         ('水tick',BASE+'water.gd','record_tick'),('初始化与native资源',BASE+'state.gd','initialize'),
         ('碰撞消费',BASE+'height.gd','physics_consume'),('换代提交',BASE+'domain_runtime.gd','_physics_process'),
         ('恢复工厂',BASE+'domain_runtime.gd','restore_checkpoint'),('原生校验',BASE+'checkpoint_codec.gd','validate'),
         ('存档路由',BASE+'checkpoint_router.gd','load_file'),('正式切换','scripts/beach/beach_scene_service.gd','_switch'),
         ('公共道具采样',BASE+'probe_codec.gd','decode'),('碰撞差异证明',BASE+'height.gd','footprint_compatible'),
         ('道具接入','scripts/props/floating_props_service.gd','attach'),('样本准入','scripts/props/floating_props_service.gd','_candidate_usable'),
         ('通用浮力与流阻','scripts/props/floating_props_service.gd','_apply_forces'),('恢复重置','scripts/props/floating_props_service.gd','reset'),
         ('道具安全关闭','scripts/props/floating_props_service.gd','shutdown'),
         ('UI投放与拾取','scripts/beach/floating_props_panel.gd','perform_action'),
         ('操作物理边界','scripts/props/floating_props_service.gd','manipulate_body'),
         ('精确旧来源投影',BASE+'consumer_checkpoint_sources.gd','project')]
def sha(raw):return hashlib.sha256(raw).hexdigest()
def build(preview_final=False):
    sources={};anchors=[]
    for title,path,symbol in ANCHORS:
        raw=(ROOT/path).read_bytes();text=raw.decode('utf-8-sig');match=re.search(r'^(?:static )?func '+re.escape(symbol)+r'\(',text,re.M)
        assert match is not None,path+'::'+symbol
        line=text[:match.start()].count('\n')+1;lines=text.splitlines();excerpt='\n'.join(f'{i+1:>4} {lines[i]}'.rstrip() for i in range(line-1,min(len(lines),line+9)))
        sources[path]=sha(raw);anchors.append({'title':title,'path':path,'symbol':symbol,'line':line,'sha256':sources[path],'excerpt':excerpt})
    for path in ['AGENTS.md','project.godot','scenes/main.tscn','scenes/playable/test1_capture.tscn','scenes/playable/test1_backwash.tscn','scenes/playable/test1_geometry.tscn','assets/unified_edit/default_catalog.tres','docs/unified-edit-extension-guide.md','docs/当前项目技术方案.md','docs/当前技术规格.md','docs/README.md','docs/主场景操作.md','docs/场景切换与功能复用.md','docs/性能面板.md','docs/knowledge/README.md','tools/unified_edit_pipeline/architecture_policy.json','tools/docs/build_execution_guide.py','tools/docs/build_unified_execution_guide.py']:
        sources[path]=sha((ROOT/path).read_bytes())
    # Spec authorities that are not method-excerpt cards still receive exact hashes.
    for path in ['layout.gd','tool_profile.gd','height_stamp.gd','profile_catalog.gd','coupled.gd','boundary.gd','cfl_decide.glsl','display_intent.gd','visuals.gd','legacy_sources.gd','unit_half.gd','water_packed_topology.glsl','water_packed_parallel.glsl','water_response.glsl']:
        sources[BASE+path]=sha((ROOT/(BASE+path)).read_bytes())
    for path in ['scripts/beach/unified_performance_panel.gd','scripts/beach/unified_scene_routes.gd','scripts/visual/water_boundary_sides.gd','assets/test1_geometry/water_cycle.json','assets/brushes/molded_material_candidate.json','scenes/unified_edit_runtime.tscn','scenes/unified_edit_height_surface.tscn','scenes/components/water_boundary_sides.tscn']:
        sources[path]=sha((ROOT/path).read_bytes())
    for key in ['main','test1_capture','test1_backwash','test1_geometry']:
        path='assets/unified_edit/presentation/'+key+'.json';sources[path]=sha((ROOT/path).read_bytes())
    for path in ['scenes/components/floating_props.tscn','scenes/components/floating_props_panel.tscn','scripts/props/floating_prop.gd','scripts/props/floating_prop_profile.gd','scripts/props/floating_prop_contact.gd','docs/漂浮道具.md','task/sandcastle_floating_props/契约/probe_ABI_v3.json','task/sandcastle_floating_props/契约/height_snapshot_ABI_v3.json','task/sandcastle_floating_props/契约/C07_UI交互.md']:
        sources[path]=sha((ROOT/path).read_bytes())
    for name in ['bottle','wood_plank','wood_stick']:
        for path in ['scenes/props/'+name+'.tscn','assets/props/'+name+'_profile.tres']:sources[path]=sha((ROOT/path).read_bytes())
    status='main默认动量B；三个test1场景默认连通排水。编辑、水tick与显示工作共用统一Pipeline。'
    cards=[]
    for anchor in anchors:
        cards.append('<details><summary>'+html.escape(anchor['title']+' · '+anchor['path']+':'+str(anchor['line']))+'</summary><p class="hash">SHA256 '+anchor['sha256']+'</p><pre>'+html.escape(anchor['excerpt'])+'</pre></details>')
    content='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Sandcastle · 统一沙水执行指南</title>
<style>:root{font-family:system-ui,"Microsoft YaHei",sans-serif;color:#e9f1f4;background:#101d24;line-height:1.7}body{max-width:1040px;margin:auto;padding:40px 24px}a{color:#8bd6f7}h1{font-size:34px}h2{margin-top:38px;color:#f4d29b}h3{font-size:18px}.tag,.phase{display:inline-block;padding:7px 13px;margin:4px;border:1px solid #506879;border-radius:6px}.phase{background:#18333c}.commit{border-color:#edbc68;color:#ffe0a5}.muted{color:#adc0c8}.panel,details{background:#172a34;border:1px solid #304854;padding:18px;border-radius:10px;margin:14px 0}select{background:#243e48;color:white;padding:8px;border:1px solid #68828e;border-radius:5px;margin-right:12px}pre{overflow:auto;white-space:pre;font:13px/1.7 Consolas,monospace;background:#101b22;padding:16px}.hash{font:12px Consolas,monospace;overflow-wrap:anywhere}table{width:100%;border-collapse:collapse}td,th{text-align:left;padding:12px;border-bottom:1px solid #40525e}button{font:inherit}.flow{display:flex;flex-wrap:wrap;align-items:center;gap:6px}.arrow{color:#87bec8}summary{cursor:pointer}code{color:#b7e6e5}@media(max-width:700px){body{padding:20px 14px}h1{font-size:26px}table{font-size:13px}}</style>
<p class="muted">本地源码生成 · 可离线查看 · 没有网络脚本或运行时写入</p><h1>同一个域，同一条沙水执行流程</h1><div class="panel">STATUS</div>
<p>四个正式场景由直接继承Node3D的统一入口加载。玩家工具只产生声明；域Runtime协调生命周期，Pipeline决定录制顺序，公共数值阶段完成候选、校验、条件提交与发布。</p>
<div class="flow"><span class="tag">场景 / 输入声明</span><span class="arrow">→</span><span class="tag">Runtime</span><span class="arrow">→</span><span class="tag">Pipeline 队列 / 3工作槽</span><span class="arrow">→</span><span class="tag">编辑 / 水tick / 显示</span><span class="arrow">→</span><span class="tag">同代完成态 / 2高度槽</span></div>
<h2>声明如何选择公共阶段</h2><p>下面只演示既有执行轨迹。选择操作和水策略会改变可见阶段标签，不执行Godot模拟。</p><div class="panel"><label>操作 <select id="operation"><option value="volume">体积增沙</option><option value="target">目标高度</option><option value="transfer">守恒搬运</option></select></label><label>水响应 <select id="water"><option value="0">0 · 关闭</option><option value="1">1 · 容量/位移</option><option value="2" selected>2 · 动量 B（main默认）</option><option value="3">3 · 原连通排水</option></select></label><p id="stroke"></p><div id="phases" class="flow"></div><p id="response"></p><p class="muted">阶段12为公共材料候选，5/6为校验，7为条件提交，8为结果；原语内部迭代不构成第二个事务。</p></div>
<h2>权威状态与读者边界</h2><table><tr><th>边界</th><th>实际职责</th></tr><tr><td>编辑执行器</td><td>只在公共决定允许时提交沙/材料等字段；拒绝保留原场。</td></tr><tr><td>水响应 / 水tick</td><td>前者共享编辑事务决定，后者拥有明确的水/侵蚀/材料子步；实际时钟由GPU完成态推进。</td></tr><tr><td>预览 / 表现 / 碰撞</td><td>读取同generation完整完成态。编辑无需等待CPU通知或碰撞收敛；消费者各自保留资源租约。</td></tr><tr><td>native保存 / 恢复</td><td>SANDUE06容器保留有效配置和原始资源字节。候选还是同一种Pipeline；完整64块新代物理槽准备后才切换。</td></tr><tr><td>关闭 / unknown</td><td>先关闭接纳，等待真实终结与最后读者证明。unknown不重放，不伪造GPU结果，不强制free未知所有权。</td></tr></table>
<h2>配置新增玩法</h2><p>新增ToolProfile资源，使用既有operation、shape、材料/水策略、数值范围和受限模板。注册表校验精确script类型并复制冻结数据；profile不得携带执行Callable、自选shader或调度器。</p><p>配置扩展方法见<a href="unified-edit-extension-guide.md">扩展指南</a>。</p>
<h2>当前方案与规格</h2><p><a href="当前项目技术方案.md">技术方案</a>说明模块协作、模拟、表现和生命周期；<a href="当前技术规格.md">技术规格</a>列出域、字段、ABI、容量、账本、兼容与验证边界。<a href="主场景操作.md">操作说明</a>和<a href="场景切换与功能复用.md">场景说明</a>对应当前四入口。</p>
<h2>main漂浮道具</h2><p>场景预存水瓶、木板、木棍各一件，右下角三槽UI选择后左键摆放/移动；拾取模式将实例收入槽位，[ / ]旋转，右键/Esc取消。固定容量3件，全部拾取后不提交空探针。交互在公共读者真实终结后换owner，重新采样目标位置并建立新观察起点，未操作物体保留运动状态。公共只读Probe → 完成态水/床/流速 → 类型化Profile逐点浮力和相对流阻 → 原生Jolt。实际state.step消耗完成水时间余额；局部保持不阻塞生产。Height ABI3用完整共享顶点上界证明5mm总床面差，未知或超限时保持道具。暂停/保存保持，成功恢复或重进重置，检查点不保存道具姿态。三个test1不投放。</p><p><a href="漂浮道具.md">道具机制与扩展</a>。</p>
<h2>当前源码锚点</h2><p class="muted">以下摘录、行号与SHA256直接来自生成时文件，可用build_execution_guide.py --check核对。</p>CARDS
<script>const op=document.getElementById('operation'),water=document.getElementById('water');function draw(){const base=[0,1,2,3];let v=op.value==='transfer'?base.concat([9,4,2,3,10,4,11,4]):base.concat([4]);v=v.concat([12,5,6,7,8]);document.getElementById('phases').replaceChildren(...v.map(n=>{let e=document.createElement('span');e.className='phase'+(n===7?' commit':'');e.textContent=String(n)+(n===7?' · 条件提交':'');return e}));document.getElementById('stroke').textContent=op.value==='volume'?'无固定笔画基准；按体积候选处理。':'公共BEGIN → sample序列 → END；固定基准与累计coverage由域持有。';document.getElementById('response').textContent=water.value==='0'?'水响应关闭，水/悬沙/动量不因该编辑被改写。':'公共水阶段：prepare → '+(water.value==='2'?'velocity_only → velocity_prepare_parallel → momentum_B':'packed → displace → velocity')+' → velocity_reduce → audit_blocks → audit_merge；与同一决定提交。'}op.addEventListener('change',draw);water.addEventListener('change',draw);draw();</script></html>'''
    content=content.replace('STATUS',html.escape(status)).replace('CARDS','\n'.join(cards))
    index={'schema':3,'family':'unified_edit','status':status,'sources':dict(sorted(sources.items())),'anchors':anchors,'limitations':'Current source and technical documentation index; contains no execution verdict or task status.'}
    return content,json.dumps(index,ensure_ascii=False,indent=2)+'\n'
def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');p.add_argument('--preview-final',action='store_true');args=p.parse_args();page,index=build(args.preview_final)
    if args.check:
        assert OUTPUT.read_text('utf-8')==page and INDEX.read_text('utf-8')==index,'Guide/source index drift; regenerate after reviewing the source change'
        print('UNIFIED_GUIDE_CHECK PASS')
    else:OUTPUT.write_text(page,'utf-8');INDEX.write_text(index,'utf-8');print('UNIFIED_GUIDE_BUILT')
if __name__=='__main__':main()
