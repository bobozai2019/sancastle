# G0–G3 阶段记录（2026-10-12）

当前为阶段结果，任务仍在执行。单快照几何已取得；编辑配对、完整负例及收尾尚未验收。数据根目录：`test_output/brush_hit_competitor/runtime_collider/20261012_probe01/`。

## 已观察事实

- 原包与 Steam 安装版 EXE / GameAssembly / UnityPlayer / metadata 大小及 SHA256 全部相同，见 `source_manifest.json`。GameAssembly 为 `147030ecf9527a25250238120364eb761390b99688b1812c4ea555b3b04e56a0`；metadata 为 `aa4457307746c4552541b6cedd4809fdaccf33eef03964a9e2300de5a09e1606`。
- `copy_manifest.json` 保存所有非 RDC 运行文件的源/副本 hash，独立副本启动；不附加用户 Godot 或 Steam 实例。
- `attempt_011029`：自有 PID 7792，GameAssembly 基址 `0x7ffefd220000`，在 PlaneChunk.UpdateMeshCollider 返回线程 19304 调用实际 sharedMesh getter；与 meshC 对象相同，vertexCount=561。该初版只存工具 hash，driver 原版本源码未封存，不能宣称所有初版执行源码完整可恢复。
- `attempt_011900`：自有 PID 16108，线程 9280。两份真实 getter 导出均有 561 个 float32 本地顶点、3072 个 int32 API 返回索引、1 个 triangles submesh / baseVertex=0，原 mesh indexFormat=UInt16。API 返回索引与底层 indexFormat 分开记录。
- 完整 localToWorld、bounds、enabled/active/layer/convex/isTrigger/cookingOptions，以及 verticesOS / readbackIndices 已保存。cookingOptions 的实际返回为有符号 -1；不擅自缩减成常见默认枚举。
- 独立脚本复验 18 份 raw hash、有限值、索引范围、bounds，以及 verticesOS 与 getter 顶点逐值相同。生成 OBJ；没有推算拓扑替代真实索引。
- 真实 Physics.Raycast 六参数重载以运行时参数类型核对，RaycastHit 大小44字节，原字段偏移及 unboxed 调整在日志中。中心/斜向/边缘同 collider 命中均对应离线几何，交点误差最大约 `8.43e-7`、距离误差最大约 `2.63e-7`，法线在1度内。冻结位置/距离容差按 bounds 对角线得到约 `1.615e-4` 场景单位。
- 第一份快照邻块尚未命中，负例失败原样保留；第二份快照邻块命中另一 collider、导出目标网格不相交，域外物理与离线均 miss。

## 失败与边界

- `attempt_011157` / `attempt_011239`：GetIndices 两参数不存在。实测当前 build 保留 `GetIndices(Int32, Int32, Boolean)`，第二项为 meshLod；后续用 lod0 / applyBaseVertex=false。不强改版本、空数组或猜索引。
- `attempt_011322`：顶点/索引已取，但部分 managed getter 被裁剪；保留 partial。
- `attempt_011400`：native icall 解析成功，但 indexFormat managed getter 不存在；保留 partial。后续从实际 engine icall 取得所缺配置。
- `attempt_012155`：Ground.planeChunks 运行时链与 16×8 chunks / 256×256 colliderResolution 已取得；当前各 chunk 的 meshC 指针相同，不能假设每 chunk 有独占输入 mesh。快照适用范围限于目标 chunk 更新完成、同线程回调期间；其他 chunk 后续更新可能改变共享 mesh 对象，不能用任意时间 getter 代替该 collider 的发布态。
- 动态最初选择了数组中间元素，但其世界位置在域边缘；未作为编辑配对。新采集按二维中心选择，等待用户正常输入。
- `attempt_012630`：添加 GC handle 时 Frida bool 参数传 JS true 报 expected integer，已修正传1；失败没有提交 snapshot。更正采集附加同一自有 PID，不重启用户已进入的实例。
- computer-use 找到自有窗口，但截图多次超时；没有依据旧截图发送输入。用户已明确同意手动进入和编辑，当前等待编辑前采集。

## 复验

```text
python tests/investigation/brush_hit_competitor/runtime_collider/verify_mesh.py --run D:/godot/project/sandcastle/test_output/brush_hit_competitor/runtime_collider/20261012_probe01/attempt_011900
```

`verification.json` 的 geometry_pass 仅指该快照几何；physical_correspondence_pass 不包含非 PlaneChunk 过滤负例或编辑配对。PhysX cooked shape / BVH、性能、原作更新频率均未取得。
