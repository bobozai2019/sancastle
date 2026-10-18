# G2 GPU 合批执行

日期：2026-10-17。结果：通过（P02 候选后端；main 尚未接线，P03–P07 未通过）。

证据：[extended.json](../../../test_output/gpu_pipeline/g2_20261017_01/extended.json)、[no_mold.json](../../../test_output/gpu_pipeline/g2_20261017_01/no_mold.json)、[extended log](../../../test_output/gpu_pipeline/g2_20261017_01/gpu_extended.log)、[no-mold log](../../../test_output/gpu_pipeline/g2_20261017_01/no_mold.log)、[manifest](../../../test_output/gpu_pipeline/g2_20261017_01/manifest.json)。首轮115项成功证据 result.json/gpu.log 保留；扩展运行另写文件。

## 交付与结论

- P02.1：async_select 从 GPU control 取实际 revision/tick，所有正常拒绝分支无条件继续下一笔；不使用 revision+index，也不检查前笔成功。async_capture 只在成功时推进实际 revision；state_seq 由批末 seal 推进。刻意传入错误的预测 revision 仍按真实 GPU 前态执行，并有 receipt 链证明。
- P02.2：候选阶段仅写 cells、water_input/candidate/scratch/receipt、材料持久工作纹理；所有验证先于沙、水、悬沙、动量及支撑提交。每种拒绝都在 RAM 对比 sand/water/sediment/momentum_x/momentum_z/mold_support/compaction 两槽共14份原始字节，未出现半笔变化。
- P02.3：新 async_editor 不调用 _make_backups/_save_snapshot/abort_receipt_batch，不建立整批14张备份，不走 CPU settlement/authorize_publication。批末在 render 序列发布沙水，再 seal；读回发布纹理等于当前完整权威纹理。旧 editor 及旧模式的回滚语义保留。材料算法6张持久工作纹理保留，不误删其局部数据保护。
- P02.4：全拒绝、首笔/连续拒绝后成功、成功A/拒绝B/成功C、后批D、湿区水候选拒绝、有/无 molded 字段均通过。A/B/C 后批D在CPU消费前已提交；最终14字段与只执行A/C/D的参考逐字节一致，沙/材料有真实变化。损坏材料支撑明确报告 GPU error_flags 并保持全部权威字段原样，后续不作为普通拒绝继续。

## 写点审查

| 字段 | 候选位置 | 唯一新模式提交条件 |
|---|---|---|
| sand双槽 | sand_prepare/apply → cells | sand_commit: r[12]==1 |
| water/sediment/qx/qz双槽 | water_prepare/displace_compensated/prefetch/apply → buffers | water_commit: r[12]==1 |
| mold_support双槽 | legacy_material_transaction phase0 → candidate_support；phase3检查r[22] | phase1: r[12]==1且范围/实际变化条件 |
| compaction双槽 | 普通自由编辑不写 compaction 权威场；phase0仅复制到材料工作纹理 | 此路径无直接写点，拒绝负例仍对比两槽 |

select/capture/seal 只改控制缓冲/测试诊断，publish只复制权威完成场到稳定显示纹理。旧事务回滚分支在候选路径不调用。GPU 正常容量/笔段无覆盖拒绝继续；非有限/负权威、身份、材料结构错误升级为异常，停止后续派发并报告。

## 复验

同 G0 引擎与真实可见 D3D12 窗口，执行 `--path D:/godot/project/sandcastle --script res://tests/integration/async_pipeline_edit_probe.gd -- --output=res://test_output/gpu_pipeline/g2_20261017_01/extended.json`，无材料轮增加 `--no-mold`。各轮单独 --log-file；不并发开GPU探针。测试只保留 JSON/日志/hash，完整场仅RAM比较，无工程副本。

适用范围：候选编辑内核与槽所有权。普通输入按帧 pump、公平水调度、碰撞、旧工具交接及保存恢复尚待后续 Gate；这些不能从本报告推断完成。未改旧96项结果、旧性能FAIL、main场景或视觉参数。
