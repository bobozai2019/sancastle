# ADR v1.16：同 tick 撤销与重做协调

日期：2026-10-11。仅 `edit_recovery_lab.tscn` 候选入口；未替换正式入口，G4 未放行。

每笔原生堆挖事务在 GPU prepare 前 capture 原格式前态；只有匹配回执经 CPU 实际量结算后，才保留前态并发布。rejected 丢弃暂存前态，transport failure 由原事务回滚/隔离，退出等待实际回执与碰撞所有权归还后释放历史。保留量继续受 v1.15 的32笔/64MiB约束，真实成本须T06。

前态 CPU sidecar 只含精确旧库存、prefix/applied长度、规范化命令及策略/速度/回执。当前实现保存原生GPU事务的 applied/rejected prefix；旧 smooth/compact 与完整检查点/跨tick重演尚未接入，不冒充完整恢复。

同 tick undo 需要暂停、空pending/零预留和最后applied前态匹配。等待现有碰撞回调及所有已结算块应用完成，再复制七字段至两物理状态；GPU复制成功后恢复原double库存并截断相应prefix，递增generation和单调revision，更新求解器/队列/碰撞代际，再发布并更新脏块相邻碰撞。等待两physics frame后返回。保留的更早前态属于同一存活prefix及未变rock/obstacle输入，重标新generation，支持连续撤销。高水位ID不倒退。

redo 重用相同几何、seed、量、策略与速度，作为新原生事务执行，使用新generation和新的int64 command ID；记录真实新命令，不伪造旧身份回执。新接受的正常终态会清除redo分支。UI生成ID先取自身intent序号与队列高水位的较大者再加一，兼容规范化命令API、撤销与将来的恢复。

暂停标志阻止候选显式advance_ticks；编辑仍可在固定tick完成。运行态undo/redo返回requires_pause，跨tick返回requires_checkpoint_replay；这只是防止错误逆操作，**尚未实现契约要求的暂停跨tick重演**。完整保存、视觉history、跨tick撤销与严格继续配对仍须后续实现，不能据此完成T05 G03。
