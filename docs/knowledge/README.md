# 可复用技术契约

本目录保存当前仍适用的单位、状态、接口、源汇、材料和恢复约束。正式入口、默认参数和兼容格式以[项目技术方案](../当前项目技术方案.md)与[技术规格](../当前技术规格.md)为准。

| 主题 | 内容 |
|---|---|
| [状态与数据](water_sand/状态与数据契约.md) | 网格、方向、单位、完成态、时钟和守恒边界 |
| [模块与命令接口](water_sand/模块与命令接口契约.md) | 统一调度、命令结果、消费者所有权与生命周期 |
| [场景与数值回归](water_sand/场景与自动验收契约.md) | 可复用地形模板、宏观误差判据和复现条件 |
| [容量侵蚀](water_sand/ADR_竞品容量侵蚀_v2.md) | 完成态速度、饱和深度权重、沉积、水库保护和时间换算 |
| [投放悬沙](water_sand/ADR_投放悬沙_v1.md) | 只改悬沙的编辑、输运、干足迹与账本边界 |
| [投碎石](water_sand/ADR_投碎石_v1.md) | 公共显示队列、1024容量、双缓冲与保存 |
| [自由挖填](water_sand/ADR_自由挖填沙_external_v1.md) | 普通名义源汇、目标高度精确源汇与搬运损失 |
| [形状刷子](water_sand/ADR_形状刷子_v2.md) | 印章、固定高度基准、肩部搬运和材料语义 |

统一协议的详细定义见[ABI v1](../../task/sandcastle_unified_edit_pipeline/契约/ABI_v1.md)、[主流程与扩展](../../task/sandcastle_unified_edit_pipeline/契约/主流程与扩展契约.md)、[配置与存档](../../task/sandcastle_unified_edit_pipeline/契约/配置与存档_v1.md)和[显示输入](../../task/sandcastle_unified_edit_pipeline/契约/显示输入_v1.md)。原作事实与项目适配分别记录，竞品资料从[统一入口](../competitor/README.md)查阅。
