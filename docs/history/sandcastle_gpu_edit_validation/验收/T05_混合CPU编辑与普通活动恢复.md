# T05 混合 CPU 编辑与普通活动恢复

2026-10-11。对应 S07：GPU dig 后保留旧 CPU compact/smooth 路径，使用同 revision 的完成态，避免陈旧绝对 patch 覆盖新沙。未执行撤销/重做。

## 实现和验证边界

`beach_recovery_entry.apply_legacy_command` 在无 GPU 事务及待处理命令时，冻结 tick 和输入准入，完整同步 sand/sediment/wetness/compaction，再通过已有 CPU 队列执行并上传旧 patch。恢复完成后重新开放原先的运行状态。保存、恢复、GPU 命令与关闭等待同一个混合事务边界。CPU 结果以既有 `legacy_cpu` 格式追加原生 prefix，保留 int64 身份；邻接碰撞块使用当前床面刷新。

本次是完整沙滩场景中调用该受保护接口的验证，不宣称所有旧 UI 输入入口都已改接此接口，也不覆盖混合操作冷启动严格继续、错误注入、并发关闭或性能。

## 证据

- `evidence/20261011_145809_beach_mixed_restore_probe`：7 项中 5 项通过，两个参考计算比较失败。检查发现探针直接把队列的嵌套 transform 命令传给 CPU Domain；Domain 要求顶层 position_m，因此参考命令被拒绝。这是探针错误，旧失败和原始 bin 保留。
- `evidence/20261011_150211_beach_mixed_restore_probe`：仅修正参考命令的 position_m 投影，实际编辑代码相同，7/7 PASS，Godot 自行正常退出。实际消费的源文件、配置、引擎和原始产物 hash 见 manifest 与 artifact_index。

重跑覆盖 GPU 挖沙，CPU 压实和平滑：两种 CPU 结果均 applied，与从当前 GPU 完成态建立的独立 Domain 参考的 R32 sand/R16 compaction 字节完全一致；目标字段实际变化，water/sediment/momentum 两分量字节不变，库存一致，全部碰撞块匹配。未来 tick CPU 请求被拒绝且 highwater/队列不变。

完整保存 prefix 顺序为 gpu/legacy_cpu/legacy_cpu，使用超过 2^53 的 int64 命令身份。随后另一次 GPU 挖沙并推进 2 tick，活动恢复使 10 个当前原生字段和 5 个 foam/bed/front 历史字段逐位回到保存态；generation 增加 1，prefix、高水位、三笔 applied log 和碰撞一致。恢复后的新 CPU compact 仍可执行。

命令：`run_beach_recovery_probe.ps1 -Probe beach_mixed_restore_probe -CompensatedCapacity -PackedRuns -CachedCapacity -PrefetchVelocity`。GTX 1050 / D3D12，真实 1920×1080 窗口，VSync 关闭，原完整负载；候选开关仍默认关闭。运行器观察超时后沿同一 PID 等到终态，无重启。

## 判定

受保护混合接口及普通活动恢复在本组输入通过；冷启动严格继续、旧 UI 接入和相关失败边界仍待验证。G4 未放行，总体 76.2% 不变，T06 正式性能与长稳仍未完成。

## 事务边界补验

`evidence/20261011_150705_beach_mixed_close_probe` 两项 PASS：分别在实际完整 CPU shadow 同步完成后及 patch 提交后启动关闭。在两个边界都尝试竞争 GPU 编辑、第二笔 CPU 编辑、保存和恢复；全部拒绝，highwater 不变，未生成保存文件。已接受的 compact 正常结束，prefix 仅两笔（GPU dig、CPU compact），无待处理命令；随后 solver/collision RD 均释放，输入和播放保持关闭，release 时间晚于边界观察。观测 signal 默认关闭，仅探针开启；不更改正常事务公式。

使用相同候选开关和 `-Probe beach_mixed_close_probe`，编译通过，进程正常退出，manifest/artifact_index 完整。此项验证关闭及竞争排斥，不等于 GPU patch 故障注入或冷恢复继续。

实际候选 `_unhandled_input` 的鼠标入口只提供 GPU 堆挖；继承的鼠标入口同样只提供堆挖，没有旧平滑/压实 UI 可迁移。S07 的 CPU smooth/compact 兼容通过受保护接口验证，不新增产品 UI 或快捷键。历史旧方法和撤销代码保持原样。

## 独立进程混合冷恢复与继续

现有 `beach_edit_process_probe` 增加默认关闭的 `--beach-mixed-cpu` 输入组，原两笔 GPU dig/place 后追加 CPU compact/smooth；仍在 tick17 保存，比较 tick24 的七 tick 继续结果。普通非混合输入、公式及门槛未改变。

- 写入：`evidence/20261011_150909_beach_edit_process_probe`，8/8 PASS。
- 独立冷恢复：`evidence/20261011_150937_beach_edit_process_probe`，8/8 PASS，加载阶段沿原 PID 等至正常终态，未重启。
- 命令为 `run_beach_recovery_probe.ps1 -Probe beach_edit_process_probe -MixedCpu -CheckpointMode write/read`，read 的 CheckpointSource 指向前一写入目录；两者均启用 CompensatedCapacity/PackedRuns/CachedCapacity/PrefetchVelocity，GTX1050/D3D12/1080p/VSync关闭。

恢复进程的 configuration/ledger/identity/pending/selection 五项篡改负例均拒绝；tick17 恢复状态及 tick24 继续状态的 15 当前/历史字段、metadata 及实际 coupled 参数/SPIR-V 合计 33 份 bin 全部一致，两个状态的实际截图像素也一致。prefix 四笔、高水位 9007199254741106 保持，generation 按恢复契约递增。原始哈希逐份复核结果见 reader 的 `raw_pair_comparison.json`，双方 manifest/artifact_index 保留。

本组未启用逐 tick readback 或备用纹理读回，不把最终一致扩大为每个中间阶段/所有输入证明。混合普通冷恢复继续在本组通过；历史非混合冷恢复间歇 ULP FAIL 根因仍未知，本次不覆盖旧失败、不宣称其已修复，G4 和总体进度保持。GPU patch 故障注入及正式性能/长稳仍待完成。

## 提交前故障隔离

`evidence/20261011_151719_beach_mixed_failure_probe` 4/4 PASS，编译及正常退出通过。正常 GPU dig/CPU compact 控制先通过，再给 smooth patch 注入空数据、保留非零 count，触发 solver 实际长度校验拒绝。未伪造回调成功；预期 ERROR `paused tool patch dispatch failed` 已保存。

修复前源码会在 patch 失败后仍追加 CPU applied prefix 并刷新碰撞，且留下 provisional CPU sand/compaction 和 applied log。现仅在 patch 成功后记录成功前缀；明确的提交前失败且 revision 未推进时恢复 CPU 临时字段及原队列历史，已准入 ID 仍消费，后端停止运行/准入。这里的历史恢复是失败事务清理，没有执行 undo/redo。

实测失败前后15原生当前/历史字段逐位一致，发布的沙/水/动量与旧完成态一致、碰撞匹配；CPU沙/压实、库存、prefix、applied log 和历史记录回到原态，失败ID 9007199254741105保持消费、队列空。后续 GPU/CPU 编辑、保存、恢复和 tick 均隔离，无保存文件，关闭正常释放 solver/collision RD。

此证据仅覆盖实际提交前校验失败；不声称已覆盖设备丢失或 GPU 提交后的部分失败。注入开关默认关闭，实际失败分支保持可观测。性能标准按ADR v1.58，未为失败测试改动数值公式。
