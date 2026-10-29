# 验收入口

当前尚无RG1–RG4执行验收。本轮只有计划编制与源文件前置核对。

计划前置核对：`../evidence/planning_preflight.json`。复跑命令：

```powershell
python 'D:/godot/project/sandcastle/task/sandcastle_test1_reverse_rebuild/tools/planning_preflight.py'
```

该脚本只读原文件头部、hash和指定符号字节位置，输出前置记录；不会建立对象索引、解码算法或改游戏。

后续实际验收报告分别为：

| 报告 | 需记录 |
|---|---|
| RG1_拆包索引与原始取数.md | 数量/失败/工具探针、复取字节/hash、原文件前后一致 |
| RG2_结论可信度与实施路线.md | 每层结论、C级、证据定位、未知与替代路线 |
| RG3_固定沙床沙滩样片.md | 三机位、连续入退浪、分项/负例、源码/profilehash |
| RG4_实时沙滩与联合验收.md | 实时操作、恢复/回归、活动成本/长稳、交付入口 |

每份报告注明日期、范围、命令/参数、run_id、原始产物、通过/未过/部分结果。捕图/工具日志PASS只证明该操作，不能代替视觉、算法或成本验收。
