# 竞品GPU编辑计算与当前项目对照

## EDIT-WATER-556-20261019：恢复实际mode6模板

本次直接复验C3只限test41 E878/E1210的核、绑定、参数和模板；不含工具身份、连续速度或性能因果。源RDC为256177273字节，SHA256 `f1794a7235a79f7a73bd6f4085bef7ecbb3a7dc39ce8a8a7aac955ee5beb3c0d`，导出前后相同。RenderDoc1.46；命令 `D:/other_software/RenderDoc/qrenderdoc.exe --python D:/godot/project/sandcastle/tools/water_momentum_lab/export_water_paint.py`。完整原始字节、selector及hash见 `test_output/water_momentum_lab/g0_replay_20261019_v2/manifest.json`，解码见同目录`analysis.json`。本机可用。

E1210仍绑定ResourceId556，实际为128² RGBA32F，262144字节，SHA256 `17faa485f5409354c6aed458c8cc8dfad1922c98532b3e0349c26f9349388261`。**本次恢复的全部R和alpha均为1**，因此不能以E878绑定的578有正负纹理变化推断本次mode6也有空间正负模板。E1210 cb138=(6,0,0,0)，36字节brush参数float[2:4]=(5,5)，中心cb147=(4.58869791,0.72305894,5.84406805)。两次独立新开捕帧的这些参数、核和模板完全相同。CS SHA256仍为`f0dea026bdaa1f44ce30dc973c7e1603fd0625c270805744e69039facf55e714`。指令138–141包含中心y的归一化；189–193为mode6速度分支。因此历史有符号模板公式的通用分支与该次有效全正R必须分开。

反证与局限：两次独立E1210完整水场hash不同，故此次未用其水场全图差分证明编辑量、冲量或工具效果。首次bootstrap在manifest创建前失败，目录保留；v2修正脚本路径后完成。没有新增“全部挖填工具都调用mode6”或“原作速度5是5m/s”结论。复验先核对全部导出hash，再用float32解码556纹理及cb/brush字节；原始和派生数据分别保留。

Godot水动量实验采用自建胶囊权重、填向外/挖向内和格心`q=h*v`，属于显式适配；没有把全白556或原作单位直接移植。该对照用于检验效果来源，不能称为完整原作水模拟复刻。

2026-10-16补充：[连续挖填卡顿的结构对照](#edit-perf-structure-20261016连续挖填的并行结构与未知成本)已按现有test41 Ground.Paint导出和当前Godot合批源码复核。下方2026-10-12的项目表格属于当时版本，不能继续将“两物理帧、逐笔等待”作为当前main默认调度；最新实现见[项目技术方案](../当前项目技术方案.md)。本次不启动竞品或GPU重放，不新增原作性能数字。

更新：2026-10-12。范围：沙、水编辑核及必要采样；不涉及业务代码。此次复取实际Compute Shader、常量字节与资源绑定，未运行原游戏或测量其真实性能。

## EDIT-COMPUTE-REVERIFY-01：test41实际编辑核复验

- 分类/可信度：观察事实C3，本次直接复验；仅限test41 E863、E878、E1210。
- 来源：`sandcastlegame/test41.rdc`，256177273字节，SHA256 `f1794a7235a79f7a73bd6f4085bef7ecbb3a7dc39ce8a8a7aac955ee5beb3c0d`。取数前后身份相同，原文件只读。
- 工具：RenderDoc1.46，[reverify_edit_compute.py](tools/reverify_edit_compute.py)。命令：`D:/other_software/RenderDoc/qrenderdoc.exe --python D:/godot/project/sandcastle/docs/competitor/tools/reverify_edit_compute.py`。
- 证据：[完整新索引](../../test_output/competitor_edit_compute_20261012_v2/manifest.json)，包含selector、输出字节数、工具/源/产物hash。保存实际DXBC、派生反汇编、完整绑定常量块与资源描述；没有导出沙水完整前后buffer、印章像素或32/36字节笔刷参数内容，因此不宣称编辑数据全量恢复。

| 事件 | 实际派发组数 | 每组线程 | 实际资源绑定 | 有效模式 |
|---|---|---|---|---|
| E863 / Ground.Paint | 32×16×1 | 32×32×1 | 印章578、32字节参数30348、8MiB沙床30347 | cb0[141].z=3 |
| E878 / Water.Paint | 16×8×1 | 32×32×1 | 印章578、36字节参数30350、2MiB水状态30349 | cb0[138]=(2,1,0,0) |
| E1210 / Water.Paint | 16×8×1 | 32×32×1 | 印章556、36字节参数30350、2MiB水状态30349 | cb0[138]=(6,0,0,0) |

ResourceId仅在此捕帧有效。E1210的印章实际绑定556，不能沿用E878的578像素解释它；该资源差异是本次新增明确定位，未恢复556像素。

E863的完整shader SHA256为`d37af2736147fd90f62ecbf8230bb0162a961ba2b16bce44a29d02fb2cdb30aa`，与历史EDIT-SAND-01匹配。E878/E1210均为`f0dea026bdaa1f44ce30dc973c7e1603fd0625c270805744e69039facf55e714`，两事件为同一编译核的不同有效模式。实际反汇编为`cs_5_0`，明确是Compute Shader，不是把像素着色器绘制结果推测为compute。

复验：按manifest重新打开同hash捕帧，选择对应事件后取Compute reflection、dispatchDimension、dispatchThreadsDimension、GetConstantBlock及resource descriptors，比较完整bytecode hash。模式整数分别从cb字节偏移2264（141×16+8）、2208（138×16）读取；这些偏移相对本次导出的cb0，不能跨捕帧直接套用。

反证与边界：全域派发不等于全部单元产生非零变化；反汇编是派生指令，不是原始HLSL。首次工具尝试无manifest，状态保存在`test_output/competitor_edit_compute_20261012/attempt_status.json`及源码副本；第二次改为显式工具路径后完成，不覆盖首次失败。当前另有主场景probe负载，因此此次不讨论重放或游戏帧成本。

## EDIT-COMPUTE-REVERIFY-02：这些Paint核是按单元修改，不含本项目式全域顺序归约

分类：指令观察C3；“更适合并行、可能更便宜”的性能解释为C1待测。

- E863反汇编指令0以ThreadID.xy形成单元索引；指令14采样印章；指令136读取对应stride16沙记录；指令149–151读取笔刷第0条记录字段；最终指令286写回对应记录。整个核包含多个模式分支，不能把所有分支都归入当前mode3。
- E878/E1210指令189选择mode6/7/8/2；190–193处理mode6速度，202–205处理mode2量字段；237写回对应水记录。
- 这两个完整编译核中没有`loop/endloop`、`sync`、原子归约或`dcl_tgsm`声明。结合ThreadID单元索引与输出，未见本项目index6那种单workgroup遍历65536格、lane0顺序补偿累加的算法。
- 沙Paint派发524288线程、水Paint派发131072线程，覆盖本帧整域；效果由印章、范围、权重和模式选择。不能称其为局部脏区派发。

复验：查本次e863/e878/e1210完整反汇编、manifest实际模式和线程规模；按有效分支核对输入输出，不凭核名下结论。

反证：这里只覆盖两个Paint核。别的compute pass、CPU准备、粒子处理或辅助采样可能承担额外工作；不能宣称整个原作没有归约、没有体积管理或零同步。指令数量/并行结构不能替代原生GPU时间戳。

## 原作计算含义与本项目差别

以下算法含义沿用[模拟与编辑方案](模拟与编辑方案.md)的EDIT-SAND-01、EDIT-WATER-01；完整前后快照仍是历史确认，本次只恢复核、绑定与常量，未重新证明整域变化及体积。

已捕获的Ground.Paint mode3按高度印章让沙高趋向目标高度，再按权重混合和限高；历史目标形式包含`center_y + 1.2×(2R−1)`。这不等同于“严格挖取指定m³并分配到桶内”。Water.Paint mode2让量字段趋向指定值，mode6按有符号模板修改速度；物理单位、原作全局水量结算与动作关联未知。

常规Water.UpdateFloor、VelocityIntegration、HeightIntegration、Advection等核是另一条更新链；不能用它们的存在证明上述两笔水编辑之后已经按真实秒数自然扩散，也不能把test41不同mode绑定的纹理当成同一印章。

| 比较项 | 竞品已确认范围 | 当前Godot项目 |
|---|---|---|
| GPU执行方式 | 实际cs_5_0 Compute Shader；Unity包内ComputeShader对象与历史字节码匹配 | GLSL `#[compute]`，RDShaderFile取得SPIR-V，经RenderingDevice compute pipeline执行 |
| 沙编辑 | 本帧高度印章＋少量参数，直接修改GPU结构化沙床 | 指定体积命令，局部权重/容量计算，多轮分配，再提交GPU状态 |
| 水编辑 | 本帧逐格量字段与速度模板修改 | E3守恒水位移、速度响应、全域检查与回执合并 |
| 主要并行结构 | Paint覆盖整域，按ThreadID修改单元；两核没有全域循环归约指令 | index6/7只派发一个workgroup；index6对全域分块加载、lane0顺序归约，index7处理湿分量与容量 |
| 可见状态 | 历史证据：编辑后的GPU沙床随后供沙面VS读取 | CPU结算授权后发布稳定沙/水/动量纹理，避免未结算状态可见 |
| CPU边界 | 已证实AsyncGPUReadback缓存、同步GetData入口、碰撞网格更新；是否每笔等待未知 | 每笔128字节回执、CPU账本结算、碰撞更新及两个物理帧后释放事务 |
| 性能 | 原生实际毫秒数未知 | 本项目旧短测挖沙GPU约24–29ms，其中沙约0.4ms，水两重核各约12ms；非此次复测 |

Godot源码定位：[沙核派发](../../scripts/simulation/edit_validation/gpu_sand_editor.gd)、[水核派发](../../scripts/simulation/edit_validation/gpu_water_editor.gd)、[顺序速度归约](../../shaders/simulation/edit_validation/water_velocity_prefetch.glsl)、[湿分量位移](../../shaders/simulation/edit_validation/water_packed_cached.glsl)。CPU边界参照[命中与Readback代码补证](笔刷命中检测_代码补证.md)HIT-PATH-03/04；不调查库存等竞品业务流程。

## 对性能取舍的意义

不是“本项目没有使用Compute Shader”，而是当前shader承担了更多精确结算与全域归约工作。竞品Paint提供了“按单元高度印章和局部速度模板”的明确参考，可以为[性能取舍方案](../history/project_snapshots/sandcastle性能取舍分析.md)提供候选方向。

若选择这种方向，应先把本项目的局部近似候选单独实现和计时，规定沙量、水量及库存误差；不能把竞品的0.045、速度5或场景单位直接当本项目米制参数，也不能从没有观测到回执推断可以删除所有同步。现有生产算法与冻结契约此次未改变。

## EDIT-PERF-STRUCTURE-20261016：连续挖填的并行结构与未知成本

- 更新日期：2026-10-16。范围：test41 E863 Ground.Paint已导出字节码及反汇编、当前main普通挖填合批的沙水计算；不读取或追踪竞品业务方法。
- 来源身份：test41为256177273字节，SHA256 `f1794a7235a79f7a73bd6f4085bef7ecbb3a7dc39ce8a8a7aac955ee5beb3c0d`；本次流式只读hash与2026-10-15manifest一致。E863 DXBC为8916字节，SHA256 `d37af2736147fd90f62ecbf8230bb0162a961ba2b16bce44a29d02fb2cdb30aa`；反汇编12528字节，SHA256 `7ba2525261dd9cefe754baa7c4c9d93d7f33da07afebfcf3f8f512aeef083e45`。
- 分类/可信度：Ground.Paint指令结构为C3，本次核对既有完整导出；“因此原作连续编辑更流畅”的性能因果仍为C1待测。Godot部分为当前项目源码和已有测试记录，不冒称原作实现。
- 已确认：该Ground.Paint使用32×32×1线程组、按线程对应单元读写；完整编译核没有loop/endloop、sync、原子归约或线程组共享声明。它没有本项目速度审计中“单workgroup循环65536格、lane0顺序累加”的结构。该结论只限所选Ground.Paint，不证明整个原作没有归约或同步。
- 当前项目：E3每笔仍执行全域水响应与速度检查，`water_velocity_prefetch`只派发一个64线程工作组，循环1024批加载65536格，lane0顺序完成补偿累加；`water_packed_cached`同样为单工作组、包含分量与容量处理。当前合批只减少上传/回执/收尾次数，没有把逐笔计算合成一个并行核。已有实际批次metrics记录挖/填核心沙水派发分别为23/12次，不含选取/回执helper、材料、发布和碰撞。
- 证据定位：[本次身份和可用性索引](continuous_edit_comparison_sources_20261016.json)、`test_output/competitor_stamp_20261015/replay_01/manifest.json`与`paint.asm`；Godot源码和实际批次记录由索引关联。2026-10-12的`competitor_edit_compute_20261012_v2/manifest.json`当前路径缺失，本次未重新取Water.Paint E878/E1210，保留其历史确认范围，不声称本机导出链全部恢复。
- 复验方法：先比较源RDC、DXBC及asm大小/hash，再核对`dcl_thread_group`、线程索引/输出及完整指令中的循环/同步/原子/共享声明；Godot核对release_config实际选核、间接派发参数和原始批次metrics。此次只读文件，未新开重放；今后重放需独立英文输出目录、同hash捕帧和对应事件。
- 反证：竞品仍有AsyncGPUReadback缓存、同步消费入口、碰撞Job.Complete和MeshCollider发布的历史直接证据；不能据Paint并行就称其零CPU同步。高占用率不是低延迟的直接证明，CPU/GPU监控口径、帧尺寸、输入轨迹和画质也未配对。
- 未知：用户观察到竞品连续编辑占用较高但不卡、本项目占用低而卡，是待定量的现象。原作同输入帧时间、每笔延迟、回读/碰撞节奏、GPU各核毫秒数，以及当前Godot长帧中各项精确占比仍未知。
- Godot适配建议：优先定位单工作组长核、全局RD帧fence、每批资源分配和队列积压；保留守恒/下限/错误预算与碰撞版本边界。详细分析见[连续挖填卡顿分析](../search/continuous_dig_stutter_20261016.md)。旧RDC结论、旧FAIL和专项验收均不改写。
