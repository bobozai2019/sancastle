# ADR v1.21：旧工具混合执行记录与重演

2026-10-11。numeric候选，G4未放行。

smooth/compact保留原Domain.apply_tool、ToolCommandQueue和GPU绝对patch路径。每次旧工具先同步当前GPU R32 sand/h/sed及R16 wetness/compaction影子，避免seed初始CPU float32与实际half完成态差异。同步与旧工具操作期间禁止新admission和显式tick推进；仅接受当前tick且无pending的同步旧工具请求，未来请求明确拒绝，不能产生未纳入scheduler的孤立队列项。

混合prefix以backend=legacy_cpu标记，保存原完整CPU结果和实际execution_tick/stock_before。外层status/generation仅作统一执行记录，不是128byte GPU回执；原CPU result（包括rejected的null applied_tick）原样保留。GPU项仍走原真实回执链。legacy结果验证和重演使用原CPU算法及上传路径，不把smooth/compact迁移到GPU、不修改权威水/动量/账本。

最后applied是旧工具时，undo使用一致anchor的完整重演；GPU之后的旧工具也参与原/目标字段与精确账本配对。redo prefix pool接受明确的旧工具命令，amount_m3可缺省（其语义不用该量），不修改原规范化命令。独立进程恢复/混合redo已验。

旧工具高度上传后，对dirty chunks及八邻块同步更新共享边缘碰撞，等待两physics frame再开放输入。影子回读关闭后不解码空结果，实际十字段回调归还计数后释放solver。已完成旧工具终态仍保留，不将CPU结果伪装为GPU回执。

未完成：完整沙滩foam/front历史、重演关闭与时间继续推进后的redo、完整成本及长稳。原CPU undo_stack的既有行为和容量不修改；其成本须纳入T06。本ADR不放行正式入口。
