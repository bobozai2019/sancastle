# T05 跨 tick 重演与恢复关闭

2026-10-11。numeric候选，未放行G4。GTX1050、Godot4.7.2、D3D12，960×540窗口；证据目录含manifest/source与artifact hash、完整字段bin及日志。

064315_scenes：`-CheckpointRestoreExit`，2项PASS。真实新候选分配/原始复制完成、提交前关闭，candidate和旧solver均rd=null，无残留build或candidate，旧库存不变；发布后关闭，返回closed_after_restore_publish并保留已恢复库存，新旧solver均释放。JSON包含实际观察阶段、账本和事件；不推断GPU完成时长。

065257_scenes：`-CrossTickUndo -FastFullWet`，首轮4项PASS。实际队列接受ID1 tick2 C及ID2 tick0 E，以ID2→ID1顺序执行；tick4 GPU再拒绝ID3。篡改已记录的前库存使原分支重演冲突，拒绝提交，当前十权威字段/两发布纹理、账本、generation和旧solver保持。复原记录后严格重演原完整prefix到tick4，再撤销ID1和其后的rejected尾部，仍保留tick4。

撤销后prefix只含ID2，与单独从同anchor执行ID2并运行至tick4的完成分支逐位相等；五账本、全部碰撞和实际射线一致。第一次提交清空快速GPU前态后，下一次undo使用anchor回退，移除ID2并匹配空prefix四tick参考；高水位保留3。

065524_scenes：当前扩展7项PASS，新增redo目标原始水字节冲突，拒绝提交并保留当前空分支及redo栈；连续两次跨tick redo逐位恢复仅ID2的分支和原ID2/ID1/ID3 rejected完整分支。目标字段/账本先经真实重演核对，tick4、碰撞、库存及高水位一致。隔离worker全部关闭，重演GPU history字节0；未计为性能收益或原作算法证据。

保存/restore源码身份加入anchor与重演控制器后须重新捕获检查点，旧证据保留按其manifest版本复验。待完成：磁盘redo/历史恢复、legacy混合、完整视觉history、重演关闭专门覆盖和T06；T05 G03仍进行中。

065828_scenes：加入自动anchor及重演输入记录后，恢复关闭2项回归通过。065908_scenes：默认慢路径（未启用fast_full_wet）跨tick撤销/重做7项回归通过。

070403_scenes：自动anchor/source身份变更后，实际保存边界及state/CFL在途关闭6项受影响回归通过。
