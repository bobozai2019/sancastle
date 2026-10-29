# T05 快速撤销跨时间 redo 与磁盘配对

2026-10-11，Godot4.7.2/D3D12/GTX1050，960×540可见窗口。各目录位于本任务evidence，包含源码/资源hash、原始字段/PNG、日志及artifact_index。性能门未据此判定。

074512_scenes：`-AdvancedRedo -FastFullWet` 五项PASS。原有跨tick redo先验证tick3后继续tick5及独立原分支配对两项回归；新增真实同tick undo保留目标、redo使用ID2与原字段/账本一致；再次同tick undo后推进至tick3，redo双分支校验通过；结果与独立从anchor执行实际prefix至tick3的十原生字段、两发布纹理及五账本逐位一致，碰撞对应当前沙面。

074621_scenes写、074634_scenes读：`-FastRedoProcess -FastFullWet -CheckpointMode write/read`，独立进程两项写/四项读PASS。实际GPU E事务→同tick undo→保存redo目标。读进程恢复后当前字段/账本/像素一致，同tick redo使用ID2且与写进程原样配对；再次读盘后推进三tick，目标水hash冲突拒绝且字段/账本/tick/栈长度保持；恢复正确目标再redo，与写进程完整原分支tick3的字段/账本/碰撞/像素严格配对。

074709_scenes：`-ReplayExit -FastFullWet` 三项PASS。原undo/redo临时worker真实CFL在途关闭回归通过；新增同tick undo目标十字段snapshot实际pending>0时关闭，返回closed，最后state回调先于release，solver释放且pending为0，原库存/prefix保持且redo为空。

以上未覆盖完整沙滩后端。T05 G03保持进行中；显式undo整图异步捕获仅在暂停恢复路径，不是编辑热路径，其成本尚未测量。

074735_scenes：不启用FastFullWet的默认路径，AdvancedRedo五项全部通过；覆盖同tick新身份与跨时间严格重演，不仅实验优化分支。
