# 水中加沙与堆挖性能调查报告

2026-10-16新增[连续挖填低占用卡顿分析](continuous_dig_stutter_20261016.md)：结合当前合批短验、单工作组水归约、竞品Ground.Paint指令结构及Godot主队列/飞行帧fence机制，列出候选原因、区分观测与适配顺序。本次仅分析和文档，没有新增运行或性能PASS。

可复用的竞品确认结论已整理到[统一知识入口](../competitor/README.md)。本目录保留原调查过程、Godot对照与历史限制；test41实际调用以v2新增证据为准，原作性能/守恒未知项不因整理而关闭。

本目录集中保存本对话的调查报告，更新于 2026-10-11。test41/test42 的当前结论以 **v2 修订版**为准，初版保留用于追溯。

| 报告 | 内容 |
|---|---|
| [水中加沙与排水调查](underwater_deposit_report.md) | 竞品水沙计算核、当前项目大块加沙的排水响应与单变量对照 |
| [堆沙与挖沙性能调查](edit_performance_report.md) | 竞品 GPU 沙床编辑、读回实现，以及当前项目卡顿证据 |
| [test41/test42 补充调查（v2）](edit_performance_test41_test42_v2.md) | 实际沙笔刷与专用水笔刷调用；区分直接证据与尚未知的动态因果、性能 |
| [test41/test42 补充调查（初版）](edit_performance_test41_test42.md) | 历史版本；修订涉及的因果置信度以 v2 为准 |

报告从 `docs/history/sandcastle_test1_reverse_rebuild/analysis/` 移入；仅调整链接，调查结论、可信度、测量值及验收判定保持原文。原始 RDC、取证数据和机器索引仍位于原目录，报告中的证据链接已指向实际位置。

[迁移清单](migration_manifest.json)记录各报告的旧路径、新路径、迁移前后 SHA256 和链接替换。历史机器索引与工具脚本保留原路径及 hash，定位报告时使用该清单映射；迁移不代表重新取证或通过验收。

返回[项目现状](../README.md)。
