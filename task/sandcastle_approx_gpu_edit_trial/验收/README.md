# 验收证据入口

角色：verification_evidence_index。2026-10-12交付完成：独立实验场景和T00–T05工作完成；局部GPU预算限定样本达标，1–2帧反馈目标未通过/真实像素反馈未确认。生产入口保持原样。

| 报告 | 内容 |
|---|---|
| [T00隔离与冻结](T00_隔离与冻结.md) | 签名扫描、复用边界、冻结参数、同态初始夹具 |
| [Gate1/Gate2](Gate1_Gate2_功能与顺序.md) | 静态场景、库存/队列、输入、epoch、复位关闭 |
| [Gate3](Gate3_模板与连续观察.md) | 三模式净量、干湿/限幅/边界、受控五分钟 |
| [Gate4结论](Gate4_成本与交付结论.md) | 分阶段GPU/CPU、两组三对短窗、适用范围与未知项 |
| [操作与复验](../../../tests/experiments/approx_gpu_edit/README.md) | 直接启动和复验命令 |

原始机器输出在 `test_output/approx_gpu_edit_trial/<英文run_id>/`。每run保留 command.txt、stdout.log、stderr.log、result.json；较后run含 candidate_sources.json、validation.json、实际profile、初态字段hash。成本run新增 gpu_processes_before.json；最终长观察和诊断开销窗口含 gpu_telemetry.json。全部结果的派生统计为 [run_summary.json](../../../test_output/approx_gpu_edit_trial/run_summary.json)，可由 analyze_runs.py重建。

早期功能run缺完整来源manifest/字段身份时只作为功能初证，不用于同态因果结论。direct_20261012_022522 是独立场景直接启动120帧的真实命令与退出日志。CPU发布/绘制、GPU执行和操作日志PASS含义分别报告。

保留的无效/失败结果：functional_20261012_013848_716141 查询超上限；cost_20261012_014554_766549 非受控UI输入；cost_20261012_015327_700691 基线缺domain_id导致未编辑。早期3秒启动探针没有受控标记，不当正式成本。原始文件及操作PASS日志不回写，派生汇总按完整证据判定接受或排除。

计划见[总纲](../总纲.md)，进度见[执行状态](../执行状态.md)。契约不得填写实际测试结果。
