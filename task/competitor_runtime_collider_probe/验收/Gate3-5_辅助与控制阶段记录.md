# G3–G5辅助与控制阶段记录

日期：2026-10-12。角色：verification_evidence。当前17/18，B级，G4 partial，goal active。

run：`test_output/brush_hit_competitor/runtime_collider/20261012_probe02_aux_control`，自有PID13344；实际agent/driver/请求/版本/hash/raw索引及失败均封存。原包/Steam八个核心文件后查不变。

| 验证 | 结果 | 边界 |
|---|---|---|
| T03-G02完整辅助 | PASS | 四份65536×32缓存，真实getter高度与四sandAmount均值最大误差0 |
| T04-G02初始物理与负例 | PASS | attempt_020105三条正例、域外、邻块及真实非PlaneChunk组件null过滤 |
| 后续控制射线 | FAIL/保留 | attempt_020652的g1_15/22边缘最近hit属于其他collider；中心/斜向通过 |
| T04-G03单次编辑 | PARTIAL | run01人类报告两次挖/堆，run02没有单次操作记录；均不能单笔归因 |
| 静默控制采样 | 观测完整/静默未证明 | 48.598秒、351次左键松开、端点相机相同，最大采样空隙1.597秒，未确认所有输入静默 |
| T05阶段归档 | PASS | 两attempt索引、原始数据/派生产物分开、源后查、进程终态及统一知识已更新 |

复验：`verify_mesh.py --run <attempt_020105>`；`verify_mesh.py --run <attempt_020652> --snapshot-ids snapshot_g1_15 snapshot_g1_22`；`verify_control_interval.py --run <attempt_020652>`。精确命令/hash见机器报告。verify_mesh退出码只表几何完整，不等于射线全部PASS。

当前无竞品实例；spawn owner按时退出，helper未kill。D3D11未修复sky截图失败。等待操作者就绪后开启最后受控单次编辑；不启动无人配合的新实例。最新OS创建身份保护仅编译验证，不冒称已运行。

已确认事实、selector、反证及未知项见[统一记录RC-MESH-05–07](../../../docs/competitor/运行时碰撞网格取证.md)。旧失败与旧阶段验收保留。
