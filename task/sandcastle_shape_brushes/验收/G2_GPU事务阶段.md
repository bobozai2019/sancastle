# G2 GPU事务阶段证据

2026-10-14，Asia/Shanghai。T02 G03/G04完成，T02累计4/5；G05进行中，G2未通过。此前[资源与路径阶段](G2_资源与路径阶段.md)保留其当时状态，本报告续接真实GPU实现。

## 实现及边界

新brush_gpu使用既有solver的receipt_pending/publication_pending/active_ticket/state_revision锁和CPU结算授权。beach_gpu_entry只新增可重载编码入口，默认仍为原128字节编码；实验派生入口选择256字节协议。正式main尚未换入口。

六阶段begin/prepare/reduce/validate/commit/rollback真实编译并在D3D12执行。每stroke从当前rock+sand复制R32F基准，清空RG32F覆盖缓存，token绑定generation；结束失效token，固定池留存至关闭。候选先归约并校验，bounded dry wall仅作为框架正例；不代替T03截面/转角/覆盖验收。castle/shovel尚不支持，湿编辑明确拒绝，材料/q/water当前不写。回执确认前公开sand保持原值，CPU结算后原发布/碰撞链确认revision。

新schema已有prefix时保存明确拒绝brush_checkpoint_not_implemented，active stroke拒绝brush_stroke_active。零新刷子恢复后的helper重绑定尚待G05检查；新刷子检查点/undo/redo完整整合属于T08，不能由本报告宣称完成。

## 实测

证据根：D:/godot/project/sandcastle/test_output/shape_brushes/。

| 内容 | 结果 | 证据run |
|---|---|---|
| 静态lab、固定场、无基准拒绝、旧GPU填沙 | 7项PASS | 20261014_031653_framework_f7eef3e7/lab_entry |
| GPU基准/候选/归约/发布/生命周期 | 45项PASS | 同run/gpu_framework |
| 提交后传输故障回滚 | 14项PASS | 同run/transport_failure |
| 错ticket回执回滚 | 14项PASS | 同run/identity_failure |
| 规范、旧库存和旧128协议 | 408+12+18项PASS | 20261014_031540_contract_1151e014 |
| 参数/协议/CPU路径 | 41项PASS | 20261014_031543_input_c876b2fd |

GPU每阶段保存27场raw及hash，包括当前十场、八个备用场、公开沙/水、基准/覆盖、foam两槽、bed两槽、local_front。验证基准实际等于fixture床面、不改权威场；零段/repeat no_change逐字节不变；有效候选体积与receipt在动态eps内一致、source只结算一次、revision只加一、collision确认；candidate error16、budget error9和old generation不改权威/备用/历史场。新候选CPU回执被测试层暂扣期间，公开场和账本保持旧值，solver tick被共享锁拒绝。

两类故障都在GPU已经产生status=applied和正沙增量后触发。故障前备用沙中心设为0.25，当前沙为1.0，防止用当前槽覆盖备用槽伪装回滚。恢复后27场逐字节匹配各自preimage，账本、prefix、revision为零，锁释放，关闭资源释放；另保存4MiB cells、256字节GPU原回执和三个backup纹理，证明不是候选原先被拒绝。

池32 RID，显式纹理/SSBO共6,570,496字节（不含driver/pipeline内部成本）；下一stroke复用相同池，baseline_copy_count=2，关闭全部释放。最后一次baseline提交到读回为121,672微秒，只是该次异步延迟，含帧调度/排队，不能称GPU耗时或正式性能通过。实际可见1280×720、GTX1050、D3D12，engine路径虽为Godot_v4.6.2，实际版本为v4.7.beta.custom_build.dff2b9bb6；硬件/VSync/SPIRV/hash见manifest与gpu_framework_evidence.json。

最后run的source_drift_after_run.json确认运行期间来源hash无漂移。原manifest/artifact_index保存命令、源码和产物身份；新补的漂移检查文件有独立角色。其他时段共享collision代码仍有外部改动，G05须重新核对。

## 故障及修复证据

- TXN-B01：024225失败，helper的_set与Object虚方法冲突；改为_uniform_set。024643证明初始化。
- TXN-B02：025254失败，过宽文本替换误改RD的compute_list_bind_uniform_set函数；修正具体调用，原失败保留。
- TXN-B03：025522测试过早判断队列已settle，空回执被误读；等待pending/input_running/pumping消退。025738正例通过。
- TXN-B04：030552、031129、031242身份故障的CPU账本未结算，但纹理未回滚。backup raw证明备份正确，复制返回OK仍不足以证明GPU效果。identity_compute亦失败；先call_deferred转至主线程，再call_on_render_thread提交rollback compute，并等待其后coverage读回才解锁，identity_deferred通过。可复验区别是相同正候选/错ticket/不同备用preimage，27场hash是否一致。结论仅限本次实测callback提交路径，不泛化所有Godot texture_copy。
- TXN-B05：031530四个脚本检查均PASS，runner仍失败：PowerShell大小写不敏感的FAIL匹配了检查名中的failure。改成词边界FAIL，仍检查非预期ERROR和report.pass；预期日志仅剔除该job声明的完整错误行，原stdout/stderr原样保留。031653聚合80项PASS。

以上失败目录不回写；直接diagnosis运行另存原始数据，正式验收以031653 runner为准。

## 实际入口及未完成项

```powershell
powershell -NoProfile -File tests/shape_brushes/run_shape_brushes.ps1 -Group framework
powershell -NoProfile -File tests/shape_brushes/run_shape_brushes.ps1 -Group contract
powershell -NoProfile -File tests/shape_brushes/run_shape_brushes.ps1 -Group input
```

下一步G05：迁移已失效旧lab探针到当前fixture，零新刷子对照、旧工具账户/顺序/队列、重复回执、恢复generation和关闭冲突。全部对应证据完成后才通过G2。T03–T09均未计完成；旧性能FAIL及严格恢复历史判据保持原样。
