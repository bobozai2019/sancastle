# T05 完整沙滩同tick撤销重做

2026-10-11，Godot4.7.2/D3D12/GTX1050，1920×1080完整release侵蚀/材质/foam/front与80浪计划；完成tick17暂停编辑。

新候选 `edit_beach_undo_lab.tscn` 静态继承完整恢复场景，`beach_undo_entry.gd` 接入双槽GPU前态、隔离候选撤销、真实fresh-ID redo和Ctrl+Z/Ctrl+Y。旧完整场景及生产solver/shader未改变，不把这个入口作为G4放行。

每种B/C/D/E先真实挖0.02m³入库存，再按该策略放0.01m³；D使用+0.25m/s，E使用−0.25m/s。保存base/edited/undo/redo完整原生检查点及15字段bin、1920×1080 PNG。undo核对当前/spare/foam/bed/front、五账本、prefix、选择与高水位；redo核对23原生字段hash、五账本、fresh-ID真实prefix和全部碰撞高度。undo重建全64块；redo仅要求各块达到实际requested revision，未脏块不要求人为递增tag。高度始终逐R32采样相等。

中间证据保留：

- `20261011_095833_beach_same_tick_undo_probe` 24项报告FAIL：四个复合redo断言错误要求所有块tag统一递增；真实redo返回成功、原生目标和八组像素配对通过。修正测试的requested-tag判据，没有放宽高度或原生字节。
- `20261011_100125_beach_same_tick_undo_probe` 24项通过。
- `20261011_100434_beach_same_tick_undo_probe` 26项通过，增加连续两次undo、两次redo；明确等待前态render释放回调，第二次操作不靠假定一帧内已消费。

上述中间版本恢复字段时使用历史revision，尚未覆盖v1.16单调revision要求，不据此确认当前完整协调器验收。当前版本已改undo revision=current+1，并在完整断言中显式核对，后续运行结果另记。

当前 `20261011_100804_beach_same_tick_undo_probe` **26项PASS**，日志无SCRIPT ERROR/ERROR：四策略完整undo/redo、八组1920×1080像素逐位配对、两次连续undo/redo和跨tick快路径拒绝、每种关闭历史释放。每次undo明确核对revision=edited+1，generation+1，高水位不倒退；redo真实ID递增，完整字段/账本目标严格相同。D策略通过实际Input.parse_input_event触发Ctrl+Z/Ctrl+Y完成方法，未绕过输入回调。

失败注入 `20261011_101134_beach_undo_failure_probe` 初次启动FAIL：运行时set_script重置继承场景export参数，profile fixture不匹配，未执行计划中的读回故障。确认自有PID19172与该脚本/独立输出路径后终止错误目标，原日志保留；改为静态 `edit_beach_undo_fault_lab.tscn`，启动失败立即返回报告。

当前 `20261011_101318_beach_undo_failure_probe` **3项PASS**：第27次真实请求返回ERR_UNAVAILABLE，其余26次实际异步读回完成；undo返回capture_failed，当前23原生字段逐位保持，库存/prefix/generation及owner不变。pending/内存capture清空，ready和accepting关闭，历史1份、redo空。实际shutdown释放历史/solver/碰撞，释放时间晚于最后原生回调。预期故障仅在测试子类抑制对应push_error，不抑制其他错误。

后续[redo回退与撤销读回关闭](T05_完整redo回退与撤销读回关闭.md)另3项验证目标不符回退、fresh-ID重试和10实际前态读回在途关闭。

跨tick仅验证快路径拒绝且库存/prefix保留，完整暂停重演仍未实现。磁盘redo、旧CPU混合、更广失败/关闭、冷首笔反馈、ULP严格继续和T06仍未完成。

复验：`tools/run_beach_recovery_probe.ps1 -Probe beach_same_tick_undo_probe`。观察60秒返回live PID时检查同一目标；测试自身最多300秒用于四种完整场景与连续操作。产物source/binary/tool/命令及索引分别记录。功能结果不支持成本结论。
