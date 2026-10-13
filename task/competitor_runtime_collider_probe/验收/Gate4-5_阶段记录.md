# G4/G5 阶段记录

日期2026-10-12。当前B级阶段结果，完整goal保持active；不得把阶段收尾当A验收。

核心产物：`test_output/brush_hit_competitor/runtime_collider/20261012_probe01/attempt_013417/`，实际source owner为`attempt_012630/owner.json`，自有PID8908。before=`snapshot_1`，after=`snapshot_18`。289顶点/1536索引/512三角形，身份/变换/拓扑/xz一致，289个y变化。实际setter序号86→4438，分别的读取前后全局序号不变。源metadata的FaceID偏移、原命中字节及共最近面验证消除了邻面法线假失败；旧verification保留。

中心/斜向/边缘同collider命中和域外miss/邻块hit负例，在两份快照均通过几何对应。中心真实命中height变化，按相同原点复算距离可对应床面变化；当前ray原点各自从bounds上方生成，不能直接比较两份原始distance当床面差。

输入条件：用户协助进沙滩，先回复已堆沙，随后纠正挖堆执行两次；按合并动作记录。后快照在确认后采集。相机投影/深度变化，背景模拟未隔离。`dynamic_temporal_pair`真实取得，但`dynamic_edit_pair_pass=false`；非PlaneChunk collider绑定过滤未执行，辅助ReadbackCells可用性尚未检查。T04/G4不得PASS。

临时指针宽度handle的get_target及释放记录均成功。旧尝试32位handle释放失败保留；其残余对象随自有进程退出释放，不倒写旧错误。所有自有采集session均已终止：`attempt_012728/cleanup.json`与`attempt_012630/cleanup.json`记录退出PID8908，其他采集记录detached。当前进程盘点无Sandcastle；本任务未向用户Godot发送停止命令，结束时初始Godot PID21316已不在清单，退出时间/原因未确认。多helper的定时收尾使该实例结束；后续应由单一owner控制生命周期，attach helper仅detach，避免较早helper提前结束新采集。

原包与Steam版8项核心源文件后查hash与前查相同；14个attempt的成功、partial、错误、raw与工具进入`seal.json`和`evidence_inventory.json`。启动日志记录游戏自行写LocalLow profile，因此不声称用户目录没有变化。没有停止用户Godot、没有修改项目正式场景/shader/profile/模拟/碰撞语义。

可靠结论已写`docs/competitor/运行时碰撞网格取证.md`并更新入口；PhysX内部cooked形状/BVH、性能与发布频率仍未知。

```text
python tests/investigation/brush_hit_competitor/runtime_collider/verify_mesh.py --run D:/godot/project/sandcastle/test_output/brush_hit_competitor/runtime_collider/20261012_probe01/attempt_013417
python tests/investigation/brush_hit_competitor/runtime_collider/seal_evidence.py --run D:/godot/project/sandcastle/test_output/brush_hit_competitor/runtime_collider/20261012_probe01
```

下一步按原目标补实际非PlaneChunk collider负例、受控一次输入及无输入对照，检查可得的ReadbackCells；不以已有阶段结果缩减原完成条件。
