# T05 完整redo回退与撤销读回关闭

2026-10-11，Godot4.7.2/D3D12/GTX1050，1920×1080输出完整release profile；功能结果不作成本证据。

`20261011_101845_beach_undo_boundary_probe` 加载FAIL：probe的pending_at_close成员与父类冲突，无功能结果JSON；日志与索引保留。改名后工具增加独立check-only编译阶段。

当前 `20261011_101925_beach_undo_boundary_probe` **3项PASS**，编译与运行日志无SCRIPT ERROR/ERROR，完整源码/工具/binary hash、实际参数、PID及artifact_index保留。

第一项：完成tick17真实E挖沙后undo；把保留目标的sand hash改为有效长度的错误值，确保真实redo发生后目标核对失败。回退后当前/spare/foam/bed/front、五账本、prefix与原基线逐位相同；64碰撞块严格匹配，generation从2到3，revision从基线53经真实redo54再回退55；新ID已消费且高水位保留。失败redo新前态已释放，redo分支保留，后台可操作状态恢复。返回redo_target_mismatch是预期失败，不标为applied成功。

第二项：恢复正确目标hash后重新redo成功，使用下一个新ID9007199254741105，实际prefix记录它，redo清空、GPU历史1份；未重复使用失败尝试的身份。

第三项：新场景完成真实E编辑，在undo实际提交10张GPU前态读回时发起shutdown。undo返回closed，未提交目标；库存/prefix/generation保持。关闭时pending10；请求关闭31604883μs，最后主线程字段回调31677013μs，历史释放31677299μs，owner释放31677600μs。结束后读回0、历史逻辑bytes0、solver/碰撞rd为空、输入关闭。

上述是当前完成态和所有权顺序观察C3。尚未证明跨tick重演、磁盘redo、旧CPU混合、更广redo失败注入、严格继续ULP或性能。

复验：`tools/run_beach_recovery_probe.ps1 -Probe beach_undo_boundary_probe`。故障目标是测试中对内部记录的单因素改动，不是实际外部checkpoint结构验收。
