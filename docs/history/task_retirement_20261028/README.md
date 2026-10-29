# task 保留资料索引

技术结论已归入[竞品知识](../../competitor/README.md)。历史资料不作为当前技术方案，旧未完成状态保持不变。

- [知识审查记录](../competitor_knowledge_audit/审查结果.md)：审查前正文、失败记录及检查结果。
- [水求解任务状态](../competitor_water_solver_evidence/执行状态.md)：原计划、契约、请求与验收。
- 复验源码：`tools/competitor_water_solver_evidence/`。
- 原生构建证据：`docs/competitor/evidence/water_solver_task_work/`。

[逐文件映射](migration.json)记录345份文件的旧路径、目标、大小与SHA256。267份唯一资料已复制并核对hash；28份运行副本文件与sandcastlegame原文件完全一致，复用原文件；50份Python缓存无需保留。没有需要接入Godot的模型、纹理或音频。

历史文档、索引和脚本保持原字节；其中硬编码路径及历史相对链接需按映射定位，工具再次执行前必须调整输入输出路径。未恢复原已缺失数据，未提升任何结论可信度。task删除命令被自动审批策略拒绝，原目录尚在。
