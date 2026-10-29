# T05 GPU 撤销前态原语

2026-10-11，候选层，T05 G03 仍进行中。

复验：`tests/edit_validation/run_scene_probe.ps1 -GpuHistory -FastFullWet`。原始证据 `evidence/20261011_061114_scenes`，3 项 PASS；manifest 和 artifact_index 保存命令、源与产物 hash。GTX1050、D3D12、Godot4.7.2、可见960×540窗口；不是正式性能测试。

初态植入非零 sediment、R16 wetness/compaction 与正负 q；E 编辑实际改变 sand/water/qx。GPU capture 后应用真实事务，再同 tick 恢复，十权威字段与两发布纹理逐位等于初态；切换物理 ping-pong 读取，七保存字段同样逐位相等。重复 capture 与错 tick restore 拒绝。私有未初始化 water_receipt 不属于初态等价门。

容量测试为原语级连续 capture/finish，不冒充34笔真实编辑：淘汰至32笔、最旧保留ID3，逻辑payload50,331,648 bytes，暂存峰值51,904,512 bytes<67,108,864上限；拒绝/丢弃 pending 不增加 retained bytes；release 后记录、pending 与 bytes_owned 均归零。

首轮 `061009_scenes` 的测试错误调用不存在的 publish_water，render operation未返回；终止该自有测试进程并保留日志及hash。候选 publish_sand 已同时发布沙与水，修正测试后061114通过。原语运行时没有CPU全图回读；测试在边界取全字段是验真行为，不计为热路径。

待完成：真实事务自动 capture/finish、库存与命令prefix撤销、generation切换、碰撞更新、暂停跨tick重演、严格保存恢复及全字段继续配对。未宣称T05 G03或G4完成。

候选纹理 COPY_TO usage 变更后，061131_scenes 原生沙水事务12项回归通过，含预期transport故障回滚；原权威事务验证未被存储标志修改破坏。
