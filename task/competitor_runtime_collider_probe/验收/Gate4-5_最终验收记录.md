# G4/G5最终验收记录

日期：2026-10-12。角色：verification_evidence。**A级，18/18，原任务范围完成。**

## 实际数据与判定

源版本沿用契约同hash，Frida17.23.3 / Python3.13；最终自有PID12856，OS创建2026-10-12T14:39:21.6340180Z。实际D3D11。run03/attempt_224222记录加载agent/driver/hash、模块和所有原始数据；原spawn owner为attempt_223920。完整原包/Steam来源身份及前后hash见run03 source_manifest/source_after。

目标chunk `0x2469d16a200`、collider `0x246e67f6c40`（ID-42414）、sharedMesh/meshC `0x2469d03eea0`；当前Ground数组成员index59。正常桶挖沙前后snapshot_g1_8/10的实际setter返回序号2004/2516，读取线程7588。getter前后绑定未变化；输入Mesh共享，取数贴着目标UpdateMeshCollider成功返回。

两份各289个float32顶点、1536个API int32索引、512三角形、1个triangles submesh，源indexFormat UInt16、baseVertex0；完整localToWorld平移(-0.9375,0,-0.9375)，前后对象、索引字节、XZ、变换与相机端点一致。enabled/active=true、layer6、convex/isTrigger=false、cookingOptions=-1（含义未解释）。完整32768×32 ReadbackCells与辅助数组保存，七个float字段有限；四sandAmount均值与实际getter y最大误差0。

中心/斜向/固定边缘三条实际Physics.Raycast前后均与真实输入几何对应；最大交点误差4.18e-7场景单位、最大法线角差0.01644度，沿用冻结容差。域外miss、邻块命中另一collider通过；初始快照真实非PlaneChunk collider ID32880、GetComponent返回null并过滤，raw44字节匹配。没有修改场景layer、禁用collider或创建fixture。

## 正常编辑与可信度

用户确认“已挖一次，镜头和鼠标未动”，随后纠正“用的桶，需要按下拖动抬起”。按原任务的一次正常桶挖沙操作记录；鼠标拖动是正常输入。实际26份按下hit raw，其中19份目标命中均逐字段核对；InputSystem采样分两段，转换原因未知，不能声称只有一个硬件按下事件，也不将其当两个桶操作的直接证明。没有追踪桶业务代码。

全操作前后间隔12.8085235秒，289个y变化，范围[-0.3815243,+0.0467954]；紧邻同chunk无按下采样对照6→8为12.7523001秒、114个采样左键松开，变化[-0.0257409,+0.0488071]。显著局部下降与实际桶目标命中交叉支持正常编辑贡献C2；背景未完整扣除，不声称每个y变化都由桶造成。中心/斜向/边缘世界命中分别改变约0.05316/0.01811/0.02311场景单位。

几何/身份/物理查询为C3；正常一次桶操作归因为C2；采样状态转换、精确硬件输入数、背景净贡献为C0。第一子区间8→9变化与背景近似，报告保留，不能单独作编辑PASS。最终取完整正常桶操作8→10，非仅时间不同的配对。

## 复验和产物

证据根：`test_output/brush_hit_competitor/runtime_collider/20261012_probe03_single_edit/attempt_224222`。

- `verification_baseline.json`：真实负例与单快照几何。
- `verification_bucket_pair.json`：8/10完整几何和物理对应。
- `verification_bucket_control.json`：6/8等长对照。
- `bucket_action_verification.json`：输入raw逐字段、相机/索引、对照、射线变化及用户操作记录。
- `snapshots/`、`canonical_raw_index.json`、`raw_index.jsonl`、`sealed_raw_index.json`：来源/原字节对应。
- `derived/snapshot_g1_8.obj`、`snapshot_g1_10.obj`、`mesh_pair.png`：派生产物，预览已打开检查。

精确命令和脚本hash见各verification；复验依次运行verify_mesh.py指定上述snapshot IDs/report-name，再verify_bucket_pair.py。默认verify_mesh不宣称单次因果，最终专用审计和本人工验收共同支持G4，不以退出0或PASS标记替代证据判断。

## 收尾与历史

原包/Steam八个核心文件前后hash相同。run03全部attempt的成功/失败、10个attempt索引及工具加载副本保留；PID7188缺失原因未知，failed attach记录保留；最终PID12856按实际创建时间和owned副本路径核实后退出。helper只detach，所有自有session已terminal。未停止其他用户进程，未改Godot正式场景/shader/模拟；游戏正常运行自身的LocalLow写入仍可能发生。

G0–G3此前通过，G4以上通过，G5独立复验、源后查、终态与[竞品统一归档](../../../docs/competitor/运行时碰撞网格取证.md)完成。A仅指本任务输入网格与正常编辑取数成功，不含PhysX cooked shape/BVH、全域批量、性能或Godot整合。
