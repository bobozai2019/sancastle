# G6 native候选物理恢复组件

日期：2026-10-18。角色：verification_report。本组件通过，**G6仍未通过**，总进度24/36，T06仍0/4。正式三入口未改。结果与完整来源身份见[组件JSON](G6_native候选恢复组件.json)。

## 当前通过的范围

统一`Pipeline.configure_restore()`先完整校验目标配置、native容器及新generation，再冻结独立副本。初始化直接使用原始current/spare字节，恢复实际control、f32时钟、state_seq/tick/revision和command highwater。`restore_verifier.gd`固定35份回读全部返回且逐字节相同后，候选才可提交；没有创建旧solver/editor、旧形状执行器、rollback、旧碰撞读回或私有preview后端。

| 用例/结论 | 原始定位、独立复核与反证边界 | 可信度 |
|---|---|---|
| 真实native容器恢复及第二次操作 | `g6_restore_gpu07/restore_native`从两笔编辑和一次真实coupled tick后捕获25份GPU数据，保存/加载真实SANDUE06容器，再创建新代次候选；35份回读、64块实际HeightMapShape及后续编辑/tick与未恢复参考域相同 | C3；只验证候选及独立新物理面，不代表当前主场景已原子切换 |
| current/spare、原生half和f32边界不被重算覆盖 | `restore_distinct`明确构造原生边界fixture：四个half场循环全部15362合法编码，spare momentum/flux额外含f32负零及最小次正规数；GPU回读保持字节，未将此人工边界fixture冒称原运行帧 | C3；数值核后续合法演化不要求保留输入位型 |
| 普通与模塑黏聚参数分别消费 | `restore_cohesion`陡沙峰、普通参数0.025；冻结environment、checkpoint及state值一致，真实48B slope push的offset28为该参数，offset32仍是模塑0.9；后续所有物理字节与持续运行参考一致 | C3；仅新增此参数的配置消费，其余环境/物理系数仍须后续整合 |
| 未完成回读不可提前就绪 | `restore_hold`将35份实际回读暂扣；initialized/ready均false，提交拒绝；重复同key和未知key回调不减pending，放行后才完成；完成后的迟到回调不二次完成 | C3；重复/未知回调为明确注入，原字节来自真实GPU |
| 取消、坏回读和unknown不损坏当前域 | `restore_cancel/registration/corrupt/unknown`保留当前域全部25份快照，随后当前域仍能编辑；失败候选不就绪，正确保留原错误，最终八类owner全部回0 | C3；未覆盖实际场景保存、当前材质换绑和全部运行中关闭边界 |
| 已释放对象不可重新初始化 | `g6_early_gpu02`三例：初始化前取消、初始化前释放、未配置就释放；迟到双重initialize不创建RID、不开放提交、不推进工作；独立178项 | C3；无GPU分配，因此不制造GPU完成凭据 |

当前8类恢复矩阵及相关6组GPU运行合计31例、963项探针检查；恢复独立2126、早期生命周期178、初始化303、coupled56、half226项及骨架5例原字节复核均通过。配置/真实旧档数据回归87项、运行参数类型/范围及零分配负例22项通过。

六组GPU运行共同149份来源hash一致，均与本次冻结源码相同。`g6_restore_final_sources07`七份ZIP保存native/early/initialization/spine/coupled/half/configuration来源及原manifest，全部成员CRC和SHA256复核。数据配置归档也包含其真实旧档fixture原字节。范围、精确条目数、引擎/命令、hash和原始数据索引均见组件JSON；不把归档操作成功当作功能或整个G6通过。

## 已修复的恢复清理问题

UEP-RESTORE-CLEANUP-001：`g6_restore_gpu02/restore_registration`自动清理未取得有效idle凭据，资源正确保留但首次清理未完成，探针退出时发生泄漏，原失败保留。`g6_restore_diagnose03`确认所有回读已返回、工作/高度均无在途、views可释放，首次idle serial1回读却是16B全零；显式经主线程重试后收到真实serial2，全部资源释放。定位：该probe的`observations.unexpected_cleanup`与`observations.cleanup`。

观察事实为C3。结合RD回调调用位置及只改变调度位置的对照，推断为C2：本机D3D12的回读回调交付阶段内追加dispatch/readback读到了旧proof缓冲。修复将恢复验证结果先交给主线程，再调度render清理记录；`g6_restore_cleanup04`三类失败通过，最终gpu07的取消、注册失败、坏回读均在第一次真实serial1确认后清理，unknown注入则保留至显式重试。适用范围是本机4.7.2/D3D12已复验路径，不外推为所有后端或所有异步API的通则。

失败源码见`g6_restore_failed_sources/gpu02.zip`与`diagnose03.zip`，原manifest保持FAIL。已变化的两份旧源码通过已知改动逆变换恢复，**只有与原manifest的SHA256完全一致才入档**；未改工作区，也没有改旧结果。`g6_restore_sources01/05/06`为各阶段快照，当前证据以final_sources07为准。

早期gpu05/06已验证相应物理字节和清理，但其范围分别早于普通黏聚参数核对、最终终态保护，不作为当前全部义务通过。普通黏聚checkpoint字段不再误与模塑材料0.9比较；旧half失败、G5原失败及此前组件均原样保留。

## 实际复验

从项目根目录执行，输出目录必须全新，真实GPU串行；引擎固定为`D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe`。

```powershell
& ./tools/unified_edit_pipeline/run_gpu_contract.ps1 -OutputDirectory <fresh-native> -ProbeScript res://tests/integration/unified_edit_restore_probe.gd -Cases restore_native,restore_distinct,restore_cohesion,restore_hold,restore_cancel,restore_registration,restore_corrupt,restore_unknown
python -X utf8 tools/unified_edit_pipeline/verify_restore.py --run <fresh-native> --output <fresh-native-audit.json>
& ./tools/unified_edit_pipeline/run_gpu_contract.ps1 -OutputDirectory <fresh-early> -ProbeScript res://tests/integration/unified_edit_early_lifecycle_probe.gd -Cases early_cancel,early_release,early_release_unconfigured
python -X utf8 tools/unified_edit_pipeline/verify_early_lifecycle.py --run <fresh-early> --output <fresh-early-audit.json>
```

参数CPU probe为`tests/integration/unified_edit_runtime_configuration_probe.gd`，使用headless运行并传入新输出目录下的`--output=.../probe.json`。当前相关回归实际目录为`g6_init_gpu03`、`g6_restore_spine03`、`g6_restore_coupled02`、`g6_half_gpu05`、`g6_restore_configuration02`和`g6_runtime_configuration02`。

请求窗口1280×720，实际设备D3D12 Forward+/GTX1050；本轮没有整帧或最终性能结论。自有GPU探针全部终结，仅用户原编辑器PID23948保留，未操作其输入或生命周期。

## 继续执行的范围

1. 实现生产端一致快照、账本结算、笔画结束和正式保存API，不能把探针中的容器构造当作已完成主流程保存。
2. 验证后原子切换实际材质、预览/UI与物理面。当前用全新的物理面验证，旧完成序列较大的当前物理面不能直接复用revision检查；候选不能在切换前影响当前碰撞。
3. 接入启用的local-front/foam/gravel、prescribed boundary/waves及剩余有效模拟参数；当前这些未完成能力仍明确拒绝，不静默丢弃。保留test1_geometry tide_mode3现有边界。
4. 完成queued/recorded/完成未消费/物理未应用/预览在途下保存、切换、关闭，连续tick的实际预览就绪和十轮完整生命周期。
5. 正式三入口接线及旧writer/fallback退役，随后G7配置扩展/架构审计和G8完整可见负载成本/长稳；不得以本组件替代。
