# 历史任务记录与迁移说明

2026-10-11 GPU堆挖专项成果已迁入[专项归档](sandcastle_gpu_edit_validation/README.md)，方案、契约、验收和关键结果摘要保留；按用户要求不保留全量中间数据。当前主场景不依赖task，复验工具在tools/gpu_edit_validation。水材质自然感任务仍在task中运行，本次未迁移。

竞品已确认技术的统一检索入口为[docs/competitor](../competitor/README.md)，整理正文与本机证据可用性分开记录；这里的历史报告和原始验收判定保留。

当前项目进展与未完成项见[项目现状](../README.md)。

水中加沙、堆挖性能及 test41/test42 的四份专项调查报告已统一移至[调查报告目录](../search/README.md)；旧路径与迁移前后 hash 见[专项迁移清单](../search/migration_manifest.json)。

2026-10-11 将 `task/` 中的 432 份 Markdown 文字记录按原相对目录移到这里，并机械调整了 96 个跨目录链接。随后将其中 3 份仍有效的冻结水沙契约移至[知识目录](../knowledge/README.md)，原路径保留迁移指引。旧任务的结论、状态、失败结果和可信度标记没有改写；test1 最后状态为 **14/15、RG4 暂停且未通过**，见 [收尾记录](sandcastle_test1_reverse_rebuild/收尾记录.md)。这些文件是历史记录，不是新的执行计划。

正式沙滩场景依赖的 shader、网格和 profile 已移至 `res://assets/test1_beach/`。迁移后 profile 的资源路径和文件 hash 已变化；旧报告里的 hash、`res://task/` 路径和运行命令只对应迁移前的证据，不能用于验证当前文件。固定参照图移至 `res://tests/fixtures/visual_water_alignment/`，测试的新输出目录为 `res://test_output/`。

文字记录中有指向 PNG、JSON、日志、原始对象和 RDC 快照的相对链接。另保留了 test1 收尾记录及 RG1–RG4 验收报告直接链接的 56 份小型附件（约 15.4 MiB）与 8 份 RG1 复取样本（约 8.6 MiB）；其中部分索引是**不含全部配套原始字节的历史目录**。其余机器产物目前仍在 `task/`；删除它后，相关链接和原始取数将不可用。保留的文字结论可作为历史线索，不能单独替代完整可复验的证据。若之后恢复逆向取数，应先重新核对原包/RDC 的路径与 SHA256，并按[原始数据与索引契约](sandcastle_test1_reverse_rebuild/契约/原始数据与索引契约.md)重建或恢复成对的原始数据与索引。

代码与场景迁移只处理路径依赖，没有改变水沙物理语义。原始失败结果仍在文字记录中，不因目录迁移转为通过。
