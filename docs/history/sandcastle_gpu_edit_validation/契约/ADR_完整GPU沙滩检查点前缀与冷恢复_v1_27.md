# ADR v1.27：完整 GPU 沙滩检查点前缀与冷恢复

2026-10-11。完整原负载候选，T05 G03进行中，G4未放行。

新增edit_beach_recovery_lab静态继承完整UI候选。显式save_gpu_checkpoint停止新接受和新tick，等待原tick/shadow/GPU事务与input driver完成，drain当前due；未来pending/预留仍存在时拒绝，不能遗漏已接受输入。随后复用原水源汇flush、完整shadow与原生物理/双槽泡沫/床面/front捕获。shutdown等已开始保存结束，避免释放读回仍使用的资源。

保持原SANDCP01/v1、create-only、32MiB、checksum和禁用对象反序列化。legacy int32/sorted命令投影为空，原生GPU真实applied/rejected执行prefix保存在gpu_beach_edit v1，包含原int64 ID、请求/执行tick、generation、匹配receipt、策略/speed、available、stock_before。五账本与原shadow/header必须精确相同；高水位取真实queue值，不使用旧CPU输入serial。捕获与写文件时临时空投影，真实applied_log始终恢复。

冷恢复先校验完整native字段与旧水/q/foam投影、prefix身份/数值/执行输入、零pending/reservation、五账本投影；再核对源码/资源SHA256索引、profile、Engine、GPU adapter、driver及实验fast标志。新scene使用更高generation；保留历史prefix原身份、恢复applied log和完整int64高水位，新输入不复用旧ID。原80浪计划及视觉时钟沿用原检查点语义。

此阶段仅冷恢复，不宣称活动scene隔离替换、undo/redo、混合旧工具或完整在途保存关闭已验。逐tick额外取数曾改变配对观察结果，前一批次继续出现四格沙各一ULP差异；原因尚unknown，不能以新的通过覆盖失败或放宽严格要求。继续完善复验和完整恢复整合。
