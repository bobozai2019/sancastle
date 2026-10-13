# ADR：临界库存与旧工具回退 v1.1

日期2026-10-11，候选矩阵运行前冻结。补充/修正ADR v1，不更改EPS或沙/水预算。

旧Domain.place判据是`tool_inventory+1e-6<request`；余额为负时，负数继续扣减剩余EPS额度。只看max(0,balance)会把已经借用的数值额度重新开放；一出现负余额就完全禁用place则比旧规则更严格，均不能冒称旧行为等价。

候选wire offset92传**有符号的settled-reserved余额**，double→float32向下舍入（负数不能按正float位序减1）。用户可用量仍max(0,balance)，但GPU place判据保留signed_balance+EPS。总预留按同一有符号余额检查，不把EPS按每笔重置。名义CPU判据与GPU实际量审计分开；任何实际量超余额+EPS仍拒绝，不扩大旧容差。若极限窄化造成状态差须记录并解决，不能覆盖失败。

测试初始化seed属于新初态，必须推进generation、更新backend owner_generation、重建queue高水位；不能同generation清队列再复用ID。物理资源可复用，但每case初态与gen/revision记录独立。

GPU→旧smooth/compact回退必须先同步当前sand、R16F compaction/wetness和sediment/water，再调用现有CPU Queue/patch，回写正确revision。R16F对照仅为旧compact路径的存储量化：`abs(actual16-expected32)<=0.5*ULP16(expected32)+2*ULP32(expected32)`，不用于dig/place的compaction（后者要求逐位不变），也不放宽严格恢复。ULP16正规数为2^(floor(log2(abs(x)))-10)，零/次正规2^-24。此界来自格式量化，在混合候选结果出现前固定。

GPU条件拒绝分开：generation不符→inactive_generation/flag3；input_revision不符→内部audit_failed/flag3；两者authority不变。旧v1把两者都映射inactive_generation的实现予以更正，128byte布局与其余编码不变。
