# P1～P4 当前主场景接入

文档角色：verification_result。按用户要求，将四项结构优化适配到当前正式 RG32F 动量链路；不恢复已删除的第三轮任务，不覆盖当前可配置 CFL、最大尝试次数、重试缓存、表现及交互改动。

## 生效改动

| 项目 | 当前实现 |
|---|---|
| P1 | MUSCL 悬沙在唯一 read-write R32F 绑定上原位交换；删除 exchange_sediment 分配、借用、绑定和复制派发。RG32F 动量输入保持。非 fatal 时保留 decision[5] 清零副作用 |
| P2 | exchange 唯一线程先清零支撑标志，再由独立全域 scan 判定；障碍、干格不会漏清。非 MUSCL 路径保留独立清零 |
| P3 | 新 material_finish 独立消费原坡面 SSBO，以原 uintBitsToFloat/max 写沙双槽，同时复制湿度和压实度；保留坡面生产及原纹理写入 |
| P4 | 支撑结果写回合入同一收尾，写支撑双槽；无支撑分支直接写零，不读支撑结果。Water.normalize 和完成态发布仍独立 |

正式共享核心已修改，main 与 test1_geometry 均使用该链路。四个核心文件见验收/candidate_identity.json；接入前的当前基线见验收/baseline/runtime.zip 和 identity.json，精确差异见验收/integration.diff。公共 GPU/CPU 字段、存档格式、账本和资源释放责任不变；来源指纹继续严格校验，不新增跨源码版本存档迁移。

资源实测口径为 State、MUSCL、Coupled、Views、发布和 Visuals 中实际 RID 去重：48→47 张纹理，逻辑有效载荷和 RD 纹理分配均减少262144字节，缓冲分配不变。64次尝试的标准主描述链1541→1285；一般公式为5+20×n，边界另加1。这包含零工作量间接描述，不能当作全图执行次数或性能收益。结构记录见验收/structure_comparison.json。

## 验证结果

| 范围 | 结果与来源 |
|---|---|
| 完整数值及控制 | variant_v1_comparison.json：71完成态逐字节一致，包含双槽、控制/审计、accepted-indirect、Coupled缓冲、dirty和CPU账本 |
| 一阶共享调用 | first_order_v1_comparison.json：5个支撑转换完成态逐字节一致 |
| 故障与失败清理 | negative/nonfinite 两对实际快照和故障身份一致；init_compile_v1 的真实编译失败、重复初始化与 owner 释放检查通过 |
| main 固定交互 | main_inputs_v3_comparison.json：120tick、8760成员逐字节一致；复用完整有效的 main_inputs_v1_a 基线，仅重跑受损候选运行 |
| geometry 固定交互 | geometry_inputs_v3_comparison.json：120tick、8760成员逐字节一致；造浪、铲、悬沙投放、成型沙均有实际应用回执 |
| 冷恢复 | cold_ordinary/molded_v1_summary.json：每类1 writer、3独立reader；原生字段、spare、材料、表现历史、账本和继续演算逐字节一致，仅契约允许的generation变化 |
| 当前正式入口 | main_live_v1：真实项目根目录启动；同代道具Probe采样推进，未见错误，源码未漂移 |
| 连续运行 | continuous_v1：可见窗口有效段约120.55秒，tick211→3677；暂停停止推进、恢复继续推进、关闭释放均通过，实际配置和源码未漂移 |
| 文档 | 当前方案、规格、Word内容源和HTML来源同步；Word47页逐页检查，无缺字、裁切或重叠；两生成器--check通过 |

本次没有重新进行性能 ABBA，不将已删除任务的历史百分比当作当前实现的性能结论。

## 架构和配套范围

静态核对：同一悬沙图像只绑定一次，不建立 restrict 输入/输出别名；Water 保有求解和发布职责，Coupled 保有材料缓冲及新finish程序。reset→scan→坡面→finish 的全域依赖仍由独立阶段保持，未删除跨阶段同步，也没有增加 CPU 读回。纹理删除沿原Water owner链清理；finish资源沿Coupled释放。两个旧开发探针只在中转纹理实际存在时捕获该私有成员，不捏造替代字段。

架构策略只更新本次改动的方法/文件、新finish shader及不再可达的sediment_copy登记。现有策略在本次基线已存在39项来源封印漂移；本次定向核对没有新增失败，剩余38项未擅自刷新。详见验收/architecture_integration_review.json；这不是全项目架构策略验收通过。

## 保留的失败与输出位置

首次文档渲染与main候选归档遇到磁盘空间不足；main_inputs_v1_b ZIP存在重叠条目，不作为通过证据。main_inputs_v2_b 的归档复制也遇到空间不足；两次原始结果保留。转回D盘后使用新前缀完成受影响运行，逐成员流式比较，未删除失败帧或放宽容差。formal_v3的Python包装进程在引擎退出0后中断，几何归档比较另行完成，见formal_validation_completed.json。

接入源码、原始状态、日志、命令、参数、检查点和最终报告保存在本目录；可删除副本仅在项目test_output。后续验证的TEMP/TMP、APPDATA、LOCALAPPDATA和缓存均显式指向项目内scratch；main_live_v1/isolation.json记录实际Godot user_data_dir位于D盘项目内。C盘两份本次临时目录已由用户清理；另有约435KB旧基线归档的删除被工具策略拒绝，未再向该处写入，不参与运行或验证。项目根AGENTS.md新增的写入边界按当前规则执行。

最终机器核对见[验收/final_audit.json](验收/final_audit.json)。本目录不是当前技术方案入口，当前生效说明见项目docs中的方案、规格及技术全景。
