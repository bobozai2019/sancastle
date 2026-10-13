# ADR v1.60：显式斜坡结果存储候选

2026-10-11。状态：[候选验证]，默认关闭。角色：frozen_contract。

普通冷恢复曾出现沙量/床面1ULP间歇差异；shader内完整/最小结果记录曾通过，仅写计数仍失败。这些关联未证明原路径根因，不能把诊断记录直接当生产修复。本候选改为真实的GPU结果存储及消费边界，并用完整状态、重复冷启动和成本验收判断是否可采用。

每个斜坡调用保留原公式、八个push参数、读入槽、原sand_out及dirty写入。新增binding7临时SSBO，每格存原sand及计算next_sand的uint原始位；随后同一compute list中新增consume pass，读取next_sand位并按原max(value,0)写入spare沙纹理，再由原commit消费。顺序为step→slope→consume→commit。没有CPU回读、全域强制物理同步或预算放宽。

256²每域新增524288字节临时buffer、一套consume shader/pipeline及两份uniform set。该buffer全格每子步覆写，不是跨tick输入或持久权威状态，不新增检查点字段；检查点仍保存最终23原生纹理，配置显式带staged_slope_requested。恢复候选通过同工厂重新分配临时buffer，释放流程释放uniform/pipeline/buffer；原共享coupler和shader不修改。

入口开关StagedSlope/--beach-staged-slope默认关闭，暂不与SlopeRecord/Counter/Output诊断混用。实际新增两份shader SPIR-V hash加入冷恢复的coupled参数证据，不能仅记录未使用的原slope SPIR-V。生产默认采用须完整相关验证、成本及选型决定。

公式等价不保证与原路径所有最终位相同；允许已有CPU/GPU迁移预算，但同候选严格恢复继续仍须逐位配对，不能放宽恢复门。当前候选通过也不证明原FMA/driver/同步根因。性能按用户v1.58标准，普通保存恢复/账本/碰撞/代际/关闭/稳定性继续受原契约约束。验证结果放在[验收](../验收/T05_显式斜坡结果存储与冷恢复.md)。
