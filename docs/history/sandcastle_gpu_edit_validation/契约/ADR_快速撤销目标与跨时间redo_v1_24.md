# ADR v1.24：快速撤销目标与跨时间 redo

2026-10-11。numeric候选，T05 G03进行中，G4未放行。

checkpoint候选的显式暂停同tick undo先阻止新输入与步进，异步读取十原生字段，保存撤销前完整prefix、精确五账本和十字段SHA256至redo目标，然后继续已有GPU前态恢复。只长期保留hash/执行输入，不保留整图CPU副本。编辑热路径和基础recovery候选不增加整图读回；该显式undo增加的读回成本尚待T06，不称零读回快速undo。

记录标记`same_tick_transaction=true`：同tick redo继续原规则，以新int64 ID、新generation完成原生GPU事务；时间推进后使用已验证的双分支重演，核对当前分支、核对存档tick目标hash/账本，再继续至当前tick并恢复。不得在新tick直接执行旧笔刷代替重演，不回退时钟。跨时间redo恢复原目标prefix；同tick redo生成新真实prefix，两种身份语义明确区分。

磁盘redo原v1前缀池可保存目标和可选布尔标记；标记类型不合法或缺目标拒绝。32记录上限继续有效。目标冲突不改当前状态/账本/redo栈。捕获期间关闭等待实际state回调归还再释放，不生成redo目标或开始undo。

范围仅numeric候选和原生编辑；完整沙滩GPU编辑/视觉history/关闭整合尚未完成。
