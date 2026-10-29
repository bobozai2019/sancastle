# ADR v1.17：原始检查点 sidecar 与保存边界

2026-10-11。候选 numeric/recovery fixture，未放行G4，不替换正式入口。

保留原 `CheckpointStore` SANDCP01/version1 envelope、SHA256和禁止对象反序列化规则。原schema的command_ids为PackedInt32Array且要求ID递增，不能表达已验证的native int64和按tick执行的非单调ID；旧CPU命令投影保持空，**完整native执行prefix在checksummed gpu_edit_sidecar version1**。该投影不表示native没有执行命令，只有候选codec能解释本扩展；旧schema与其原严格测试不修改。

sidecar保存十权威字段的原始R32F/R16F/R8/RGBA32F字节、实际库存和四源汇账本、tick/generation/revision、高水位ID、所有native applied/rejected命令与终态、策略/速度。保存边界pending=0/reserved=0。检验字节数、有限性、非负沙/水/悬沙、half范围、障碍字节、native身份和重复命令；旧schema投影与sidecar重建投影必须一致。读取校验SHA256，不接受损坏、陌生version或省略数据。

原始恢复仅用于隔离新求解器：通过带COPY_FROM的暂存纹理复制原始字节到候选的两套物理字段，不经过half二次编码，不修改生产solver的usage flag。复制API接受不代表GPU时长或完成时刻；后续异步全字段取证验证实际结果。待候选和元数据验证后才能切换、结算和发布；**实际入口的原子restore协调器尚未实现**。

`edit_checkpoint_lab.tscn` save入口立即关闭新接收并冻结显式tick推进，等待在途事务/输入驱动完成，drain当前tick已接受命令后捕全部十字段。仍有future pending时返回pending_commands，不改tick、不丢命令、不释放其预留，不产生成功文件。未来tick完成后可以再次保存，包含同一命令。文件存在时禁止覆盖。保存期间直接GPU命令、UI调度、撤销/重做与reset均被入口保护。

配置另存checksummed gpu_edit_configuration：引擎、实耗profile、shader源码及SPIRV身份、固定边界/Hz、候选flags、策略/速度和表现tick时间；restore入口还须核对配置兼容性。当前numeric shader无TIME/历史积累，visual_history显式为none；本断言**不适用于完整沙滩foam/front历史**，不得用空数据替代已有视觉history。

候选基础入口增加实际state/CFL异步回读计数。关闭后丢弃旧代际数据，但回调仍归还计数；render release等待计数为0，再释放求解器。snapshot/advance等待循环响应closed/generation，避免忽略旧回调后永久等待或累计关闭后的tick。观察信号默认关闭，仅供所有权探针。

当前legacy smooth/compact prefix未接入保存，save明确返回legacy_prefix_not_supported_yet；这仍是未完成项，不能据此缩小G3。跨tick撤销/重做的检查点重演、恢复的实际碰撞/发布切换、恢复失败/退出、完整沙滩视觉history与跨进程继续配对还须完成。
