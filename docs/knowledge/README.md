# 可复用技术契约

2026-10-13 main及继承的可编辑场景按用户要求采用[自由挖填沙 external_v1](water_sand/ADR_自由挖填沙_external_v1.md)：无背包依赖，实际增减量记外部沙源汇，普通恢复header v3显式标记；原库存测试与其限制仍按旧契约执行。

当前GPU编辑的字段、库存预留、结算发布、水策略及普通恢复约束见[GPU编辑冻结契约与修订](../history/sandcastle_gpu_edit_validation/契约/编辑事务与水响应契约.md)，适用范围以[主场景整合](../history/sandcastle_gpu_edit_validation/主场景整合与临时清理.md)和[归档证据边界](../history/sandcastle_gpu_edit_validation/证据保留说明.md)为准。

竞品技术事实及未知项另见[统一知识入口](../competitor/README.md)，按其[记录规范](../competitor/记录规范.md)更新；本目录仍只保存项目已冻结技术契约。

这里仅收录已冻结、仍约束当前水沙实现的跨任务契约：

- [状态与数据契约](water_sand/状态与数据契约.md)：网格、单位、权威状态、守恒账本、存档与错误语义。
- [模块与命令接口契约](water_sand/模块与命令接口契约.md)：模块边界、工具命令、排序和生命周期。
- [场景与自动验收契约](water_sand/场景与自动验收契约.md)：标准场景、测点、阈值和证据格式。

这些文件的 `frozen v1` 表示**接口/判据已冻结**，不表示所有实现或验收已通过。当前完成度与未解问题以[项目现状](../README.md)为准。视觉阶段的候选方案、test1 单帧逆向报告、性能调查和原始失败记录仍在[历史任务记录](../history/README.md)，不作为通用技术契约迁入。
