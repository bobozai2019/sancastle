# 形状刷子与材料约束

形状工具使用统一512B命令与384B结果协议，通过公共候选、审计和条件提交执行；精确字段以[layout.gd](../../../scripts/simulation/unified_edit/layout.gd)为准。profile只选择已支持的operation、shape、材料／水策略和合法参数，不提供执行回调、私有shader或调度器。

城堡使用固定世界标高的高度模板，低于目标时补足，高于目标的原沙保留；同位置重复不叠高。模板65×65 RGBA32F、采样间距0.0625m，payload、占用mask及SHA256参与冻结身份。

沙墙与铲子通过公共BEGIN保存本笔baseline，sample累计coverage，END终结笔画。默认铲子`CAPPED_SHOULDERS`中央挖沙后，两侧各接收不超过实际挖量的一半；每侧达到笔画基准以上0.5m停止加沙，未接收部分记实际沙汇。没有实际挖量时不新增供沙标记；回填后可再次铲至记录的沟底。`BALANCED_SHOULDERS`为另一种合法守恒策略，不能与默认账户混用。

局部成型材料由mold_support及材料字段表达。默认成型压实度0.95，R16F实际值0.9501953125；成型内聚高度0.9m，饱和标记深度0.125m。普通沙内聚参数独立，main为0、geometry为2m。材料与水响应共享公共接受决定，拒绝不留下半笔材料或排水。

操作预算、ULP检查、账户与恢复边界见[当前规格](../../当前技术规格.md)，配置扩展见[扩展指南](../../unified-edit-extension-guide.md)。
