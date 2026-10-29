# GPU堆挖专项成果归档

2026-10-11。用户要求将成果迁出task，中间数据不保留；本目录是历史成果归档，不是自动执行任务入口。

- [主场景整合与临时清理](主场景整合与临时清理.md)：当前main.tscn、固定v1.60/E3、原生保存恢复、十项入口验证及临时内容分类。
- [收尾记录](收尾记录.md)：方案、完成范围和遗留问题；G5未完成，性能停止。
- [G4逐项审计](验收/T05_G4_结果存储候选放行.md)：v1.60数值/交互/恢复放行边界。
- [编辑事务与水响应契约](契约/编辑事务与水响应契约.md)：字段、账本、原子提交、发布、四种水策略及版本化修订。
- [成果迁移清单](成果迁移清单.json)：迁移路径、原/新SHA256及有意不保留的数据范围。
- [证据保留说明](证据保留说明.md)：保留的摘要不能替代未保留的全部原始字节。

生产代码已在scripts/beach、scripts/simulation及shaders中，场景与资源在scenes/assets；不依赖task。实用复验工具在[tools/gpu_edit_validation](../../../tools/gpu_edit_validation)，新输出写test_output/gpu_edit_validation，原工具源码在本目录tools保留历史版本。

本次只迁出GPU专项。task/sandcastle_water_material_natural仍在运行，按用户选择保持原位置，不属于可删除目录。
