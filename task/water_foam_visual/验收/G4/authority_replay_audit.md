# 权威字段重放只读审计

结论：`authority_switch_v2/main` 的严格末端 A/A 与 A/B 均失败；`authority_boundaries_v1/main` 增加中间检查点后，各已保存边界 A/A 与 A/B 均逐字节一致。后一结果仅说明该观测节奏下的重放一致，不能视作前一失败已修复，也不能据此批准无观测运行的权威隔离。源内根因仍未知。本审计未修改运行代码、权威算法或容差，未启动额外 Godot/GPU 运行。

## 证据和比较方法

目录相对于 `task/water_foam_visual/验收/G4/`。直接读取真实 `.sandue`，通过 `VariantReader(container[48:]).document()` 解码数据，不重跑模拟。PackedByteArray 按原始字节比较。量化表将 R32F、RG32F、RGBA32F 按小端 float32 解释；flux 的差异数量为 float32 分量数量，绝非字节或像素数量。R16F 和 R8 字段没有进入本次差异表，因为它们一致。

### v2：只在每轮最终状态捕获

文件：`authority_switch_v2/main/start.sandue`、`case0_mode0.sandue`、`case1_mode0.sandue`、`case2_mode1.sandue`。A/A=case0 对 case1；A/B=case1 对 case2。每轮从相同 start 恢复，fill 后30tick、dig 后30tick，在最终90tick保存。

| 字段 | A/A 不同分量 | A/A 最大绝对差 | A/B 不同分量 | A/B 最大绝对差 |
|---|---:|---:|---:|---:|
| sand | 21 | 2.384185791015625e-7 | 15 | 1.1920928955078125e-7 |
| water | 320 | 5.960464477539063e-8 | 323 | 5.960464477539063e-8 |
| momentum_x | 734 | 3.864988684654236e-8 | 854 | 2.7939677238464355e-8 |
| momentum_z | 745 | 3.725290298461914e-8 | 857 | 2.2351741790771484e-8 |
| sediment | 599 | 4.656612873077393e-10 | 620 | 4.0745362639427185e-10 |
| flux | 1518 | 8.09086486697197e-9 | 1765 | 4.4674379751086235e-9 |

三份最终检查点的 configuration、simulation、selection、wave_requests、wave_start_times、cohesion_yield_height_m 完全相同；sim_tick=90、advanced_time_s=2.9999985694885254、revision=695、state_seq=92、highwater_id=2、ticket_id=62。ledger 完全一致。这排除了上述终态元数据的明显不匹配，尚未定位首次分歧发生在哪个 dispatch 或输入边界。A/B 与 A/A 的差异量级接近，不能证明 A/B 没有额外影响，也不构成通过标准。

### boundaries_v1：加入中间capture控制

目录：`authority_boundaries_v1/main/`。case0=mode0、case1=mode0、case2=mode1。

| 同名阶段（每阶段均有 case0/1/2 文件） | A/A | A/B |
|---|---|---|
| restored | 精确一致 | 精确一致 |
| place_sand_0 | 精确一致 | 精确一致 |
| place_sand_1 | 精确一致 | 精确一致 |
| place_sand_30 | 精确一致 | 精确一致 |
| remove_sand_0 | 精确一致 | 精确一致 |
| remove_sand_1 | 精确一致 | 精确一致 |
| remove_sand_30 | 精确一致 | 精确一致 |

命名例：`case0_place_sand_0.sandue`。0表示编辑提交完成但未再推进tick；1和30分别为该次编辑后的累计完成tick数。上述“精确一致”覆盖 native.fields、native.spare、native.foam、native.histories、native.material 的全部字段和 ledger；原始字节无容差比较。此探针新增每次request后 completed_tick恰好+1与输入end_requested清空断言，退出码由主执行者记录为0。

因此，在此探针条件下没有可报告的“首差阶段”。新增中间保存含GPU回读与等待，且探针其他断言/取值方式同时调整；尚未进行单因素消融，不能将同步屏障列为已证实根因。记录为“对观测/执行节奏敏感的未解释差异”，不将中间capture永久加入产品或作为数值修复。

## 源码只读排查范围

- `restore_verifier.gd` 核验current/spare、published/view、material、clock及相关历史，再开放输入；恢复漏写不是本轮已证实原因。
- `player_input.gd` `_sample` 使用固定seed101；没有观察到seed跟随command_id变化。
- 原 `_wait_tick` 只轮询pending/active，未自行断言完成tick增量；新边界探针补足了该观察，但未证明原失败由此产生。
- `water_packed_topology.glsl` 的DSU使用整数atomic，不能仅凭atomic认定浮点归约非确定性；`staged_slope.glsl` 使用分离输入/输出和固定邻域遍历。未在有限审查中定位可确认的权威写竞争。

## 复验入口和身份

用当前 runner 的独立 run-id 执行 `foam_authority_switch_probe.gd` 或 `foam_authority_boundary_probe.gd`，两者必须分开保存，不能覆盖旧失败。执行命令与引擎信息以各run目录command.json、stdout/stderr、probe.json为准；本审计只离线读取，不创建新的运行身份。离线复验可将各 `.sandue` 的48字节容器头之后传给下列reader，比较上述native组；float量化用NumPy `frombuffer(..., dtype='<f4')`。

审计时当前入口源码身份（不是反推旧运行时身份）：
- `tests/visual_water_alignment/foam_authority_switch_probe.gd` SHA256 `2fa2f19d3bbf094a6384bf1a9e17689150d06e782de44eb7dae8584c494d277c`
- `tests/visual_water_alignment/foam_authority_boundary_probe.gd` SHA256 `15e5c98014b5618e03ee4295a500803e21b91a88ef1ac7c0b7ba208a4e217ec5`
- `tools/unified_edit_pipeline/native_variant.py` SHA256 `ab0dc5eba5383bb13d0fcdd1368dce2db06b3fb3851913850edb6d1e550b02f0`
