# T05 重演关闭与时间推进 redo

2026-10-11。numeric候选，非正式成本。各证据目录包含完整日志、manifest/源hash及artifact_index；GTX1050/Godot4.7.2/D3D12/960×540窗口。

072523_scenes，`-ReplayExit -FastFullWet`，undo/redo两项PASS。实际隔离worker的CFL pending>0时关闭主域；worker回调时间≥close，worker release≥callback，主域release≥worker release；两个solver的rd均null，worker指针清空，state/CFL计数0。未进入目标提交，主域工具库存与完整prefix保持；操作返回closed。记录包含真实销毁顺序，不只轮询意图或状态文本。

072708_scenes，`-AdvancedRedo -FastFullWet`，两项PASS。E tick0、C tick1运行至tick3，undo C后又运行至tick5；redo先严格核对当前E分支，再核对原目标tick3的完整字段hash与精确账本，继续原目标分支两tick后提交。结果tick5、全部碰撞正确，与独立从同anchor执行完整原prefix并运行至tick5的十权威字段/两发布纹理及五账本逐位相等。没有回退表现tick或使用逆笔刷。

支持范围仅带目标记录的重演redo；快速同tick redo记录跨时间仍返回原requires_checkpoint_replay，尚需回退实现。完整沙滩foam/front history、相关整合与T06仍未完成。T05 G03保持进行中。

072840_scenes：新增存档tick验证边界和worker释放检查后，既有跨tick撤销/重做7项受影响回归通过，含原/目标冲突保持当前分支。
