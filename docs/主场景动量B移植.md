# 主场景动量 B 移植

更新：2026-10-19。实验副本经用户确认后，将其 B 公式移植到正式共享后端。

## 当前行为

正式入口仍为 `res://scenes/main.tscn`。main 默认策略2；“原连通排水（勾选对照）”默认不勾选，勾选后使用策略3。推水力度默认0.25，面板范围0–1、步长0.25；API范围仍为[-1,1]。中央水道等湿区可观察响应，干沙不产生动量。铲子需拖动生成沟槽。

策略2读取本次实际接受的床面差，采用：

`Δq = h × normalize(cell_center - closest_point_on_command_segment) × speed_m_s × Δbed / 0.2m`

填高向外、挖低向内；零距离方向为零。覆盖已参与床面候选，不重复乘权重；不乘模拟dt。无床面变化、覆盖外、障碍≥0.5、水深≤0.001m、力度0不施加该冲量。候选总速度沿用4m/s上限。编辑阶段不重分配水深或悬沙，床面改变仍会改变几何水面标高；后续水量搬运由正常浅水tick负责。该公式是本项目适配，未宣称竞品原公式。

策略3保留原连通拓扑、位移与旧局部速度公式。策略0/1及悬沙、平滑、压实的能力约束不变。公共策略2的语义随共享后端更新，三个test1入口仍默认策略3。

## 接线与事务

- `scripts/simulation/unified_edit/water_response.glsl`：仅在mode1为策略2加入B分支。
- `water_response.gd`：保留并行候选准备、速度归约、守恒审计与同一条件提交；trace标记为`momentum_B`，不执行packed/displace。
- `scenes/main.tscn`、main表现manifest和`unified_playable_entry.gd`：静态开关、力度控件、默认策略、状态同步。
- 模式/力度切换结束当前手势，从后续命令生效；已接纳命令继续使用冻结参数。保存恢复同步policy/speed与UI。

正式入口继续使用共享runtime/pipeline/executor，不依赖`tests/water_momentum_main/`私有副本。主场景的相机、四场切换、道具、碰撞和常规水沙模拟继续沿用原路径。此次来源hash发生变化；既有来源校验及受限迁移不放宽，未登记的旧存档不能无条件恢复。

## 本轮验证

实际可见1280×720窗口、Godot 4.7.2、GTX1050、D3D12，串行运行：

| 验证 | 结果及范围 |
|---|---|
| `unified_edit_main_momentum_probe.gd` | 39项通过：正式共享后端、默认B、力度、填沙/挖沙/铲沟、手势中切换、保存恢复与UI同步、水tick、释放和孤立节点 |
| `unified_edit_drainage_probe.gd` | 92项通过：水/悬沙双槽逐字节保持、实际动量变化、无瞬时位移、原排水重启、无效策略拒绝和候选不提前提交 |
| `unified_edit_water_probe.gd --case=water_nan_2` | 20项通过：NaN候选拒绝、无半提交与释放 |
| 同入口 `--case=water_fill_3` | 25项通过：旧参考水深/悬沙精确一致、动量在冻结误差预算内、非速度回执一致 |
| `check_main_momentum.py` | 填沙/挖沙各112个湿单元改变动量；独立CPU公式最大绝对q误差分别6.82e-8、2.01e-8 m²/s，均小于2e-6；生产来源hash匹配 |

本轮索引见[验证记录](main_momentum_verification_20261019.json)。原始字段、截图、存档及日志存于索引中的本机输出目录。未重跑全项目验收、长稳或性能专项；测试中的同步字段回读不作为性能证据。历史G0–G8及实验副本结果不改写为本轮结论。

复验主场景：先建立输出目录，用Godot参数 `--path <项目目录> --script res://tests/integration/unified_edit_main_momentum_probe.gd -- --output=<输出目录>`；然后执行 `python tests/integration/check_main_momentum.py <输出目录>`。
共享GPU契约探针的`--output`取JSON文件路径，主场景/UI探针取目录；原排水参考和NaN探针另传上述`--case`。

技术方案、技术规格、操作说明和文档首页已同步；执行指南由`python -X utf8 tools/docs/build_execution_guide.py`重新生成，`--check`校验当前来源索引。
