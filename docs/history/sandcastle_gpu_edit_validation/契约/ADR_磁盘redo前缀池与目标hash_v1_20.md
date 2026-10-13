# ADR v1.20：磁盘 redo 前缀池与目标 hash

2026-10-11。numeric候选，G4未放行。

检查点增加gpu_edit_redo version1，包含最多32条redo记录和共享prefix_items池。相同完整命令/终态/实际执行输入以Variant字节SHA256去重，目标prefix用PackedInt32Array索引，native command ID仍保留int64。普通同tick redo保存原命令及策略/速度；跨tick redo保存目标tick、十原始字段SHA256、精确五账本及完整目标prefix的索引，不重复存完整网格。整个结构由原CheckpointStore envelope的SHA256覆盖，32MiB上限不放宽。

恢复前校验版本、条数、索引、命令/domain/高水位、tick、策略/速度、十字段hash、账本及native replay输入。未知版本、非法引用/hash不进入候选分配，当前分支不变。读盘还原为replay_target记录；redo仍严格重演当前与目标分支，目标原始字段hash及double账本匹配后才提交。hash是原始字节等价的校验，不是画面相似度。

普通GPU快速前态没有序列化，保留完整anchor/prefix支持磁盘恢复后的重演回退。独立进程两次cross-tick redo已验；完整沙滩history、legacy混合、重演关闭和T06仍未完成。实际文件大小和编码容量见验收，不把codec容量fixture称为真实32笔编辑或正式成本。
