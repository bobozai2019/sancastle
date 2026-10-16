# ADR：形状刷子命令 v2 与独立搬运账户

2026-10-14。状态：accepted（基础架构）；材料和native字段最终内容仍待G4。本决定扩展项目接口，不修改历史128字节编辑协议及库存/自由挖填契约。

2026-10-15实现补记：brush_v2、守恒铲子、局部mold_support双槽、mixed-delta水事务、native v2/edit v4和五工具已经接入三个正式入口，不再属于“待实施”。城堡后续按用户修订采用固定世界Y标高、低填高留、重复不叠高，取消旧25cm落差拒绝，见[固定标高验收](../../../task/sandcastle_shape_brushes/验收/G5_固定标高放置.md)。本补记只对齐实现状态，不改本ADR原冻结布局/预算；C05/C07最终冻结、普通沙对照、300tick严格继续和性能遗留仍按[收尾记录](../../../task/sandcastle_shape_brushes/收尾记录.md)保留。

问题：现有remove/place二选一transport会把未知形状误解码成普通填沙，不能表达一事务的铲子搬运、单笔基准及实际双侧量。自由挖填的amount×strength权限也不能作为整座城堡体积归一化。

决定：新增BrushCommand/Result schema 2，256字节、magic/version/stride显式检查，int64身份不转float。请求与回执布局、预设范围、错误、路径生命周期与数值预算冻结在[基础细目](../../../task/sandcastle_shape_brushes/契约/G1A_冻结细目.md)。同域仍只有一队列、64 pending和一个在途写者，新增命令复用当前锁/代际/结算/发布/碰撞边界；旧ToolCommand显式legacy_v1路由，不能转成新命令else分支。

城堡/墙从几何目标补足实际沙量，按有限add预算完整接受或拒绝，实际量记sand_source。铲子donor、两侧receiver和水/材料共同校验后一次提交，removed=left+right在预先量化预算内，source/sink/inventory精确不变；不能调用两个普通remove/place模拟搬运。形状授权只在external_v1场景开启，库存模式的新schema明确拒绝；库存不足、预留、旧v1预算校验继续保留。

新笔保存固定GPU基准与有界coverage，正常end/drain后释放，恢复idle。保存gpu_beach_edit v4明确brush_schema=2、external_v1和混合backend前缀；旧v2/v3各按旧语义验证。新增材料状态时才另升gpu_beach_native版本，格式/双槽/削弱/候选回滚由G4冻结。配置签名覆盖新增代码目录、实际模板原始字节/参数、资源、shader和material profile。未知hash/version/伪造搬运账户或预算拒绝，原场景不变。

新增保形只限塑形区域，support=0及零新编辑负例必须保持原算法。第一模板尺寸4–6m是物理网格可读选择，非竞品参数。所有公式都是本项目适配。

验证影响：G1A纯数据与原账户admission；G2新旧路由/无编辑/回滚/重复回执/代际；G3/G5/G6真实几何与搬运；G4普通沙及材料；G7输入/UI；G8mixed-delta水/检查点/切换；G9三入口和5分钟连续观察。基础契约冻结不宣称以上GPU/视觉验收已通过，旧严格恢复和性能判定保持历史状态。
