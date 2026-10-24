# 当前版本数值判据核查

结论：没有找到可直接适用于本次同机、同驱动、同后端逐格水深/沙厚/动量A/B的既有非零容差。约1e-7差异仍按严格比较记未通过；没有新增或迁用epsilon。此核查为只读，不修改权威实现。

泡沫契约C04允许在量化既有A/A非确定性后按原数值契约处理，但这不自动产生通用宽容权。`docs/knowledge/README.md`明确要求旧ABI/调度/存档条款按版本阅读。

| 现有依据 | 实际约束及适用边界 |
|---|---|
| docs/knowledge/water_sand/场景与自动验收契约.md:45 | 同机同输入逐步输出一致；跨GPU/驱动才允许事先记录的数值容差，本次不属于该例外 |
| task/sandcastle_unified_edit_pipeline/契约/主流程与扩展契约.md:36、88 | 诊断开关不改权威；并行化须事先明确确定性/量化容差，未提供可套用的逐点epsilon |
| 同任务契约/ABI_v1.md:51–60 | APPROXIMATE/EXACT_EXTERNAL、2×base epsilon及ULP针对单笔体积、授权、守恒/回执，不是跨运行逐格字段容差 |
| 同任务契约/配置与存档_v1.md:39 | current/spare/material原字节初始化并回读验证；约束恢复本身，不授权后续演算偏差 |
| tests/floating_props/isolation_probe.gd:44–45 | 当前统一入口读者隔离直接比较native原始组、账本和完成时钟，无epsilon |
| tests/integration/unified_edit_checkpoint_probe.gd:219–220、240 | 恢复继续采用字段SHA和账本精确比较，其scope不能代替启用effects/boundary的正式入口验证 |
| tests/integration/unified_edit_boundary_probe.gd:93、103 | 边界继续采用字段SHA与f64账本精确比较 |

当前pipeline ABI1与SANDUE native3容器没有新增跨运行逐点容差配置。不能用守恒体积误差、跨硬件例外或旧接口测试替代本轮权威隔离。此前中间capture精确一致的结果也仍不能消除无中间capture的失败；后续单因素探针仅用于解释差异，不把capture永久加进产品来制造通过。
