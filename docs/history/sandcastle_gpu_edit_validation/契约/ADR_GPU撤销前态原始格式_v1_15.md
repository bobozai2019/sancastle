# ADR v1.15：GPU 撤销前态原始格式

日期：2026-10-11。范围为候选 GPU 前态存储原语；尚未接入撤销、正式交互或检查点。

`gpu_edit_history.gd` 仅在 render thread 操作。前态包含 sand/water/sediment/qx/qz 的五张 R32F 和 wetness/compaction 的两张 R16F；保存及恢复使用 texture_copy，不经 CPU 字段解码或上传。复制之前拒绝 receipt_pending/publication_pending 和重复 pending capture；finish(applied) 决定保留或释放。仅匹配 capture 的 generation/tick 才允许恢复，两套物理状态均恢复；发布、库存、prefix 和代际由尚待实现的恢复协调器管理。

同 tick 的堆挖事务不改变 rock、obstacle、flux；原语不保存这些字段，不允许据此声称支持跨 tick 恢复。跨 tick 仍须暂停并从一致检查点重演。R16 保留原始字节，避免 double/float32/half 再编码改变压实与湿度值。

最多保留 32 笔。256² 每笔 24N 字节=1.5 MiB，32 笔为48 MiB；暂存第33笔时49.5 MiB。按实际 bytes_owned 管理，任何新分配前检查64 MiB总额，旧记录淘汰与失败 pending 释放。该计数为纹理逻辑 payload，不等于驱动实际分配或性能成本；T06须另测真实成本。

候选 lab_solver 创建纹理增加 CAN_COPY_TO usage flag，生产 solver 不变。未默认启用历史，不把本原语 PASS 当作 undo 完成。严格恢复仍复用已有 CheckpointStore schema，加版本化 sidecar，不以此代替全字段继续配对。
