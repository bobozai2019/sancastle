# T05 磁盘 redo 与独立进程配对

2026-10-11。numeric候选；GTX1050、Godot4.7.2、D3D12、960×540窗口。每目录有manifest/source hash、完整bin/PNG、日志、scp及artifact_index。

070923_scenes writer：真实E tick0、C tick1，两者运行至tick4；保存撤销前redone字段、double账本及PNG，然后连续跨tick undo至空prefix，再保存包含anchor/redo的文件。真实redo记录2条，公共prefix池2条，文件13,268,804 bytes，低于原32MiB上限。

另造已有正确SHA256但redo索引越界、hash非hex、version未知的检查点，实际restore分别返回invalid_redo_reference/hash/payload，generation与redo栈保持。这些负例没有伪造文件读取成功为恢复成功。

071009_scenes reader：独立新Godot进程读取070923的scp，恢复两条compact replay_target redo记录；checkpoint十权威字段与两发布纹理、五账本及PNG逐位相等。执行两次redo，先核对当前分支，再核对各目标hash/账本，实际提交后redone十权威字段与两发布纹理、五账本、全部碰撞和PNG都等于writer撤销前结果，tick4且redo栈为空。reader日志PASS仅在这些实际比较均通过后输出。

复验：`run_scene_probe.ps1 -RedoProcess -CheckpointMode write -FastFullWet`，再用`-CheckpointMode read -CheckpointSource <write目录> -FastFullWet`。sourcehash改变时必须重新写入，不能绕过配置核对。

待完成：旧smooth/compact混合、重演途中关闭、时间继续推进后的旧redo分支语义、完整沙滩foam/front历史及T06。T05 G03仍进行中。

071156_scenes：writer新增明确标注的codec容量fixture，重复两条已验证记录构造32条（不冒充32笔真实编辑），仍只保存2条前缀池数据，解码32条成功，文件13,317,824 bytes<32MiB；实际两条事务和3个负例再次通过。

071311_scenes：RAM原始checkpoint和磁盘compact target共用目标hash校验后，跨tick撤销/重做7项受影响回归通过，包含原/目标冲突保持当前分支。
