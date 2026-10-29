# 水中加沙后排水与水面抬高专项调查

日期：2026-10-10（Asia/Shanghai）。问题 ID：`Q-WATER-DEPOSIT-01`、`Q-GODOT-DEPOSIT-01`。本轮为调查，未修改正式水沙求解器、工具、shader、场景或 profile；不改变 RG4 的未通过状态。

## 结论

**当前实现有明确的陡坡排水局限，用户观察值得修正；但“床面升高、先保留水深”本身不是水量守恒错误。**当前工具只改沙床，水面按 `eta=rock+sand+water` 随床面抬高，然后等待流量求解排开。对于浅水中突然出现的大高差，现有静水重构会截断低侧的重构水深，排水响应不再充分区分沙堆高度。隔离 GPU 对照中，20 cm 与 80 cm 平顶沙堆的水深演化几乎相同，逐格最大差仅 `3.73e-8 m`。

**竞品也保留了床面更新前的水量字段；现有证据不支持把差异解释成“竞品直接删水、我们保留水”。**其实际计算链使用包含床高的自由水面差更新速度，随后更新水量并搬运。本帧有三轮此类计算。它与当前通量离散方式不同，可能解释更强的排开感；但是本帧没有“大坨沙入水”的动作，无法确认原作该动作的秒数、专用位移步骤、瞬态冲量或全局守恒。

## 问题与取证范围

- 用户的视觉观察：竞品向水中加入一坨大沙后水快速散开，项目中水被抬高。作为动作外观线索为 C1，尚无可测时间序列。
- 竞品：只读 `sandcastlegame/test1.rdc` 与已有 Water ComputeShader 对象，不分析工具/UI/业务方法。RDC 前后 SHA256 均为 `761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2`；容器 `sharedassets0.assets` SHA256 为 `6dd7bb6bc7d926fd43c08d22c9c767b7edf531cf11a4a555fcd41830f2f9c721`。
- 项目：检查正式 test1 耦合入口消费的共享工具与 GPU 数值核；隔离同一数值核运行，关闭潮汐、侵蚀、表现浪与光学，避免把床形演化或显示浪混入排水时间。
- 所有原始导出、selector、hash、工具及验证在 [证据目录](../../task/sandcastle_test1_reverse_rebuild/evidence/deposit_inquiry_20261010)、[产物索引](../../task/sandcastle_test1_reverse_rebuild/evidence/deposit_inquiry_20261010/artifact_index.jsonl)。源码/profile hash 在 [分析摘要](../../task/sandcastle_test1_reverse_rebuild/evidence/deposit_inquiry_20261010/analysis_summary.json)。

## 已确认事实：竞品

### C3：Water 包内核与实际运行字节码匹配

对象 ID 为 `asset:6dd7bb6bc7d926fd43c08d22c9c767b7edf531cf11a4a555fcd41830f2f9c721:636`。导出其两个 renderer 的 22 个编译变体并反汇编，六个核与本帧实际 CS 字节码 SHA256 完全一致，故不是按名字猜测。

| 核 | test1 事件 | 直接证据 |
|---|---|---|
| UpdateFloor | 1484 | 读 `ResourceId::139571` 的 8 MiB ground buffer；写 `ResourceId::139573` 的 2 MiB water buffer |
| VelocityIntegration | 1490、1505、1520 | 三次实际 dispatch |
| HeightIntegration | 1495、1510、1525 | 三次实际 dispatch |
| Advection | 1500、1515、1530 | 三次实际 dispatch |
| UpdateAmount | 1537 | 读取 obstaclesMap、airCells，并改水量；不能据此认定封闭域守恒 |
| UpdateTangent | 1543 | 后续更新 |

详见 [运行匹配清单](../../task/sandcastle_test1_reverse_rebuild/evidence/deposit_inquiry_20261010/runtime_kernel_manifest.json)。编译字节码及反汇编不是原始 HLSL。`BlurFloor`、`SubtractFloor`、`CopyGroundHeight` 等核虽在包内存在，本帧未匹配到实际执行，不能据名字声称它们参与这次加沙。

### C3：UpdateFloor 保留当前水量字段

water buffer 每格 16 字节 uint4；第 3 个 uint 的低 24 位为水量/水深编码，第 3 个 uint 高 8 位与第 4 个 uint 低 16 位组成床高编码。逐指令跟踪可见 UpdateFloor 重写床高位，保留水量位。

另在事件 1478 后与 1484 后全量读取 131,072 格：**水量编码变化格数为 0**，床高编码有变化。直接复验结果在 [分析摘要](../../task/sandcastle_test1_reverse_rebuild/evidence/deposit_inquiry_20261010/analysis_summary.json)；原字节与 selector 在 [快照清单](../../task/sandcastle_test1_reverse_rebuild/evidence/deposit_inquiry_20261010/snapshot_manifest.json)。

限制：该帧床高变化仅约 `[-0.000253,+0.000694]` 场景单位，未捕获大体积加沙。因此它证明本帧该核的字段行为，不能排除其他动作前另有水处理。

### C3 指令事实 / C2 语义：床高参与速度驱动

[VelocityIntegration 反汇编](../../task/sandcastle_test1_reverse_rebuild/evidence/deposit_inquiry_20261010/renderer_2_VelocityIntegration_variant_0.asm.txt)分别读取邻格与中心的床高、编码水量，形成 `floor + max(amount - 0.05, 0)` 的差，再乘空间尺度倒数及系数更新速度。邻格平均、阻尼、湿干条件与速度限幅也参与，不能用一个简单梯度公式冒称完整原作公式。

首个匹配 dispatch 的有效常量：空间步长字段 `0.05859375`、倒数 `17.06666756`；时间积分字段 `0.00732421875`；加速度系数 `16`；速度限幅 `2`；邻速混合系数 `1000`。数值来自已记录 cbuffer 原字节，解释限对应被 shader 消费的分量。其他未使用字节不作配置解释。空间/时间的物理单位与游戏墙钟倍率仍未知，不能直接把这些数值当作 Godot 的米/秒或原作实测波速。

### C3：0.05 是内部偏置，不能照搬成删水阈值

水面 VS 的指令 23/32/48/56、72/78 从编码水量减去 `0.05`；几何使用床高加扣偏置后的水深，PS 在有效水深低于 `1e-5` 时 discard。见 [水面 VS](../../task/sandcastle_test1_reverse_rebuild/data/readable/rdc/test1/event_6083_vertex_disassembly.txt)、[水面报告](../history/sandcastle_test1_reverse_rebuild/analysis/water_report.md)。它不证明竞品丢弃真实的前 5 cm 水深，也不支持在项目中加入 `h<0.05` 一刀切删除。

## 已确认事实：当前项目

### C3：工具只改沙床，随后等待通量排水

- [shallow_tool_patch.glsl](../../shaders/simulation/shallow_tool_patch.glsl)只绑定并写入 sand 与 compaction，两份 ping-pong 同时更新；没有 water 或 momentum 绑定。
- `GpuShallowSolver.dispatch_tool_patch()` 对应同一行为。正式 test1 耦合场景的共享 `reference_preview.gd` 在 tick/暂停补丁中调用它；可选的固定子步包装仍调用相同物理 pass。
- 正式水面由共同床高与有效水深重建；当前 `wet_epsilon_m=0.001`。纯显示关掉水面不能排掉权威水量。
- 旧 [NUM-08](../history/sandcastle_water_sand_coupling/验收/T04_GPU_NUM08水下编辑与水量闭合_20260928.md)有意验收“编辑后水深逐格不变”，只用了挖/填 `0.01 m³`、最大床高变化约 `0.0664 m`，未测独立大沙堆的排水响应；挖后再填还会基本恢复原床形，不能替代新堆沙的时间曲线。

### C3：陡坡高差响应发生饱和

[shallow_edge_flux.glsl](../../shaders/simulation/shallow_edge_flux.glsl)第 42–54 行的 X 通量，以及第 64–76 行的 Z 通量使用：

```text
zmax = max(bed_left, bed_right)
hL = max(0, bed_left + h_left - zmax)
hR = max(0, bed_right + h_right - zmax)
```

若高床格与低床格原来水深同为 0.12 m、速度为零，当床高差超过 0.12 m 时，低侧重构水深被截为零，高侧仍为 0.12 m；把高差从 0.20 m 增到 0.80 m 不再增大这个界面的初始通量。高床中心则先保留整层水，排水从边缘向内传。

这个“坡度、格距与水深组合造成速度偏低、水深偏高”的局限已有数值分析；本项目的归因同时由本地公式与单变量 GPU 对照支持，而不是仅引用论文。[Delestre 等，2012，§2.2](https://www.numdam.org/item/10.1016/j.crma.2012.08.004.pdf)。该文讨论给定床面的流动，不独立证明瞬时投沙的全部三维物理。

### C3：GPU 隔离对照实测

条件：64²、格距 0.125 m、静水深 0.12 m、沙堆直径 1.5 m；D3D12、Godot `4.7.2.stable.steam.ed1daf0bf`、GTX 1050。使用正式 GPU 数值核，固定 `1/600 s` 子步，输出同完成态四张 R32F 纹理。时间为模拟时间，**不是正式主场景墙钟秒数或成本测量**。

| 沙形 | 0.1 s 堆中心水深 | 0.5 s | 1 s | 2 s |
|---|---:|---:|---:|---:|
| 无编辑负例 | 12.00 cm | 12.00 cm | 12.00 cm | 12.00 cm |
| 平顶，抬床 20 cm | 12.00 cm | 8.33 cm | 3.04 cm | 0.677 cm |
| 平顶，抬床 80 cm | 12.00 cm | 8.33 cm | 3.04 cm | 0.677 cm |
| 圆顶，最高抬床 80 cm | 7.37 cm | 0.748 cm | 0.186 cm | 0.064 cm |

20/80 cm 平顶是单变量对照，0–5 s 全部采样的逐格水深差最大 `3.73e-8 m`，动量差也仅浮点量级。圆顶对照改变沙形及总沙体积，说明几何敏感性，不能作为等沙量比较。平顶 5 s 中心仍约 1.17 mm，接近但仍高于 1 mm 的可见阈值。

全域初始水量 7.68 m³；全部案例最大水量闭合差 `3.13e-6 m³`，未发现负水或非有限值；未编辑负例水深逐位不变。采样 CFL 最大约 0.0284，远低于当前 0.35，故这组慢排水不靠不稳定大步长解释。未测试侵蚀、实际笔刷形状、主视角光学和全负载调度，不能宣布完整功能回归通过。

原始结果：[首组探针](../../task/sandcastle_test1_reverse_rebuild/evidence/deposit_inquiry_20261010/godot_deposit_probe.json)、[高度单变量对照](../../task/sandcastle_test1_reverse_rebuild/evidence/deposit_inquiry_20261010/height_saturation_check/godot_deposit_probe.json)、[逐格差统计](../../task/sandcastle_test1_reverse_rebuild/evidence/deposit_inquiry_20261010/analysis_summary.json)。探针 PASS 仅说明成功采集与局部数值检查。

新增 374 份产物、25 个 RDC 快照、6 个编译核映射的 [专项溯源检查](../../task/sandcastle_test1_reverse_rebuild/evidence/deposit_inquiry_20261010/provenance_validation.json)通过；[全量索引检查](../../task/sandcastle_test1_reverse_rebuild/evidence/deposit_inquiry_20261010/full_index_validation.json)复核 38 个源文件和当前 17,800 份登记产物，错误为零。38 条未解依赖及33条原有未映射候选仍保留；索引通过不等于这些未知已解决。此轮校验另存新目录，没有覆盖旧 Gate 结果。

## 推断、反证与实施建议

| 陈述 | 可信度 / 分类 | 反证与边界 |
|---|---|---|
| 当前大陡堆上水面先整体抬高、排水响应不充分区分大高差 | C3，当前代码与隔离实验事实 | 圆顶排水更快；不说明所有沙形都排水慢 |
| 原作本帧床面更新保留水量，并用床高参与速度驱动 | C3 指令/绑定/字段事实，公式语义 C2 | 未捕获大加沙动作；其他动作前处理仍未知 |
| 原作的自由水面差响应可能解释快速散开 | C1 待验证假设 | 原作机位、沙形、尺度、时间倍率及显示边界还可能影响视觉；缺匹配动作对照 |
| 单纯把项目水深重置成“旧海平面减新床高”能修复 | 不采纳 | 会隐式删水；未把排出体积交给邻格或边界账本 |

建议优先做**大床高编辑的局部保守排水适配**：记录编辑前床高/水面，按新床面计算需要移出的局部水量，把它送到可接纳的周围水格，并显式处理动量、悬沙、障碍和无出路的封闭洼地。封闭域不能通过保持海平面删去水，最终整体水位升高也可能是正确结果。这是待验证的 Godot 方案，不冒称竞品做法。

若选择修正流动离散，则针对“床高差超过水深”的局部源项/重构评估；只替换 Rusanov 通量或增加子步并不能自动消除已截断的床高差。全域增大重力、把显示水面压回水平或放宽薄水删除阈值不应作为根因修复。

实施前须记录 ADR，更新现有“编辑后 h 逐格不变”的 NUM-08 语义；保持水量/沙量/悬沙和工具账本、同 generation 完成态、暂停、撤销、恢复及检查点一致。验收应新增大堆/小堆/平顶/圆顶、封闭洼地、障碍阻挡，以及 0/0.033/0.1/0.25/0.5/1/2 s 水深与移出水量曲线。不能为了排水快让静水负例产生自发波动。

## 未知项与下一证据

`Q-WATER-DEPOSIT-01` 继续为 open：需要原作同一机位、带时间戳的大沙入水连续记录，最好同时取得动作前后床高、水量与速度 buffer，以区分专门的编辑位移、常规自由水面梯度、显示剔除和时间倍率。现有 test1 单帧与 test35 帧号差均不能代替秒数。

`Q-GODOT-DEPOSIT-01` 的“是否存在当前模型局限”已解决；如何改动并达到竞品响应仍待单独实施验收。本轮不回写旧 NUM-08 结果、不增加原任务完成数。

## 2026-10-10 试验清理

用户要求全部暂停并清理中间产物。未接入正式求解器的通量波速和局部位移试验源码、临时探针已移除；四个临时探针输出目录尚未删除，因为递归删除被自动审批策略拒绝，不能声称清理完成。它们不计入验收。本报告前面的原始调查证据与正式物理代码保持原样，`Q-GODOT-DEPOSIT-01` 仍为 open。

## 复跑

下面前三条是本次取数的命令记录。再次取数须先复制对应脚本并将其 `OUT` 改为新的英文证据目录，再运行同样的 selector 和 hash 校验；不要覆盖已登记产物。GPU 探针支持输出目录环境变量，可直接在新目录复跑。

```powershell
# 原始导出；所有输出均为英文路径，源包只读。
& 'C:/Python313/python.exe' 'D:/godot/project/sandcastle/task/sandcastle_test1_reverse_rebuild/tools/investigate_deposit_kernels.py'
& 'D:/other_software/RenderDoc/qrenderdoc.exe' --python 'D:/godot/project/sandcastle/task/sandcastle_test1_reverse_rebuild/tools/investigate_deposit_rdc.py'
& 'D:/other_software/RenderDoc/qrenderdoc.exe' --python 'D:/godot/project/sandcastle/task/sandcastle_test1_reverse_rebuild/tools/investigate_deposit_snapshots.py'

# 用新目录复跑诊断，保留已登记证据；不进行实时性能测量。
$env:SANDCASTLE_DEPOSIT_OUTPUT = 'res://task/sandcastle_test1_reverse_rebuild/evidence/deposit_inquiry_recheck'
& 'D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' --path 'D:/godot/project/sandcastle' --rendering-driver d3d12 --disable-vsync --script 'D:/godot/project/sandcastle/tests/investigation/underwater_deposit_probe.gd'
```
