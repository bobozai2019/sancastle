# 统一编辑ABI v1

显示颗粒投放采用[独立标签的显示输入v1](显示输入_v1.md)，共用工作槽和完成头。下述物理批次/命令/结果的标签、枚举和APPLIED/revision规则保持冻结；新显示数据不进入旧codec。

2026-10-18。角色：contract。T01/G1数据协议、开关及保存规则已冻结，联合390项检查通过。实际布局唯一来源为`scripts/simulation/unified_edit/layout.gd`，机器版为[ABI_v1.json](ABI_v1.json)；`protocol.glslinc`由该模块生成并在测试中逐字核对。改变布局须升版本、同步槽分配/codec/restore/故障注入并重新验证，不能按消息长度猜旧schema。

## 容量、类型与权限

| 对象 | 字节/容量 |
|---|---|
| 命令 | 固定512B，所有沙/悬沙/材料编辑和笔画控制同一信封 |
| 逐笔结果 | 固定384B，applied=1/no_change=2/rejected=3 |
| 输入批次头 | 96B；最多64命令；单槽最大32864B |
| 完成头 | 96B；单槽最大24672B；水tick为0编辑结果 |
| 所有权槽 | 3个工作槽、2个高度槽；本数据模块不分配或释放RID |
| Candidate | 每cell64B，16个uint word |
| Summary | 每块128B，256块+1合并记录，共32896B |
| 已注册配置 | 最多64 profiles、16种65² RGBA32F模板 |

little-endian。ID为positive signed int64（MAX=9223372036854775807），tick/sample等计数非负；seed允许signed int64位型。GPU使用低/高两个uint32，不经过float或shaderInt64。分配器在MAX后返回identity_exhausted；已为MAX的合法身份仍可编码。profile_version为正u32。浮点字段为有限float32，禁止非零量静默下溢为零；授权金额向下收窄。数值算法容差未改变。

API准入、GPU完成和碰撞应用是不同边界。`Intent.freeze`只验证/快照数据，不宣称队列已接纳或GPU执行；T02的submit_intent必须再检查后端/关闭/代次/有界队列。fatal/unknown属于生命周期状态，不是业务rejected，也不授权重放、结算或释放资源。

## Intent与有效配置

必填：domain_id、generation、command_id、sim_tick、profile_id、profile_version、profile_hash、start_xz_m。可选：end_xz_m（默认起点）、parameters、features、authorization、stroke_id、baseline_token、sample_index、seed、source_context。未知顶层键和未知数值参数拒绝；StringName/String只在明示的名字字段接受。

注册表解析静态catalog并缓存验证后的值/模板字节。配置快照绑定原资源/模型/模板hash。参数和受限features形成effective_hash；排队后资源修改不改变快照。features只能选择资源声明的water_policy/material_policy枚举，不能关闭identity/finite/nonnegative/conservation/atomic/consumer检查。非相应水策略下非零speed拒绝。write mask由operation/destination/有效policy推导，调用方不能自报更小权限。

authorization仅允许降低现有请求上限：体积编辑available_m3、目标高度add_budget_m3、搬运transfer_budget_m3。0是合法限制，不能被默认上限覆盖；增加上限、错用授权字段、NaN/负值拒绝。默认预算使用既有体积×strength、castle48、wall/min8公式、transfer/min1公式。授权与几何是每命令快照的一部分，不是修改资源profile。

disk/stamp要求起终点相同；stamp和形状刷子保持完整足迹域内及原baseline语义。普通disk允许域边裁剪，普通sweep有独立静态配置，最大64m以覆盖有界全域段；形状笔画仍≤2m。候选有效区域由输入包围盒和必要的累计coverage合并，不能只处理墙的最新段。原语只输出Candidate/scratch，不能写权威字段、发布、等待CPU或自行提交。

## 字节布局

所有逐字段offset、整数类型和枚举以机器表为准。摘要如下：

- Command：0–31为协议/操作/形状/目标/派生字段/受限能力；32–79为command/generation/stroke/baseline/sample/tick int64；80–95为profile版本、水/材料策略和control_kind；96–191为domain/effective/template SHA256；192–287为固定几何、数值、授权和域常量；288–319为操作策略/模板索引/ledger；320–327为seed；328–363为包围盒及模板/网格；其余必须0。
- BatchHeader：0–31为协议、count、两个stride、slot、work_kind；32–55为generation/batch/lease int64；56–87为domain hash；88–95保留0。EDIT要求1–64命令；WATER_TICK要求0命令，保留真实水沙数值阶段。
- Result：0–15为协议/outcome；16–95为命令/代次/笔画/基准、实际revision/tick/state_seq、batch/lease；96–127为slot、真实changed fields、error/phase、dirty mask及计数；128–191为量/误差/预算；192–207为真实变化矩形；208–271为domain/effective hash；272–319为水/变化诊断、ledger/invalid/coverage/sample/profile版本；其余必须0。
- Completion：绑定generation/batch/lease/slot、实际state_seq/tick/revision、完成状态/error flags、实际时间和本批accepted/rejected数量。每笔state_seq属于批末完整发布，revision链使用GPU实际前后值，不能从CPU预测前笔成功。

control_kind=BEGIN/END/CANCEL时operation=0xffffffff，保留domain和笔画身份，其余编辑参数、hash和数量必须0。控制回执为no_change，不改权威revision。未录制取消由生命周期明确标识known_unrecorded，不伪造GPU回执。模拟tick不伪装成笔刷。

Candidate words0/1是目标字段old/new，2/3是rock/water，4/5是old/new compaction，6–9是old/new tag/ref，10/11是baseline/target，12–14是weight/direction，15是touched/donor/receiver/invalid flags。Summary的净量、左右接收、ULP项、绝对变化、touched、真实脏块和材料/水非法位各自保存；27–30额外保存搬运材料所需donor/nominal项，31保留0。初版完整初始化本命令cells/summary；局部化须另证明有效范围、累计coverage和无旧数据残留。具体GPU生成/归约/提交尚待T02–T04，schema测试不证明它们已实现。

## 回执、账本和异常

只接受匹配命令、代次、租约、domain/effective hash、profile版本及实际tick的回执。applied须有真实权威变化和revision+1；no_change允许coverage-only但revision稳定；rejected必须无沙/水/材料/coverage变化。每笔变更必须在配置许可字段中，变更计数/矩形有界。常规拒绝后有效后继可保持相同input revision继续；fatal完成头只保留raw诊断，不生成普通业务结果或ACK。

ledger是显式策略：

1. APPROXIMATE_EXTERNAL：普通挖/填/悬沙按**已知GPU录制**的原请求量×strength估算记账，包含业务拒绝；不是精确物理增减。CPU保留原double请求估算，回执float32源汇仅作对应策略诊断，不用于库存。
2. EXACT_EXTERNAL：目标高度按实际量结算source/sink。
3. CONSERVATIVE_TRANSFER：搬运source/sink为0，removed、added、左右receiver和授权在原预算内。
4. UNCHANGED：平滑/材料调整/控制不改源汇；平滑仍须守恒，压实不得隐藏沙量变化。

decoder检查applied误差与随回执报告的预算、总量/授权和账本策略，但不会从缺少的每格权威值独立重算ULP预算。真实公共GPU校验及独立数值对照仍是T04验收义务，不能以codec通过替代。

T03.3实现补记：搬运仍按旧规则使用base eps，净量/双侧/供受允许2×base eps、授权允许+base eps；公共回执eps_sand/eps_transfer报告实际采用的2×base eps，布局和物理许可未变。Result数量和Summary净体积/左右接收均为m³。Summary27/28/30保留材料分配所需Σ厚度（m），29为Σ(搬运厚度×compaction)（m）；不把这些内部比例统计误作m³源汇。Candidate baseline/target仍为世界米，weight/direction未借作分配scratch。原语内部prefix和tx为私有有界scratch，不属于存档或公开命令ABI。

T03联合/T04初验补记：Candidate0/1在bed或material操作中保留bed old/new，在suspended操作中为sediment old/new；材料调整的实际目标另在4/5 compaction，不能把bed锚点解释为压实值。公共mode12生成材料，R16F量化后统一验证。水输入为私有32B/格的old/new world bed、h/s和qx/qz/obstacle；局部候选范围外从当前物理态读取。公共水归约更新实际所有适用字段的并集changed/count/dirty/bounds；Result touched为床/水审计并集，沙量预算仍使用其原床touched，没有借并集扩大沙量容差。512B/384B wire、枚举和字段布局均未改变；128B私有decision及原核参数视图不属于旧执行器transport或存档ABI。

## 旧公开格式的适配契约

适配器允许识别旧工具ID/格式；公共调度、候选选择以外的后半程、发布/碰撞/保存层不能依赖工具ID。T02实现数据适配，不允许调用旧writer。

| 旧入口/数据 | 新声明与保留规则 |
|---|---|
| schema1 remove/place + circle | dig_v1/fill_v1，XZ点、半径、量、strength、seed；world Y不进入旧高度场权重 |
| schema1 remove/place + swept_segment | dig_sweep_v1/fill_sweep_v1；保留整段体积授权，不拆成两笔或把一次量重复给每段 |
| place + suspended_v1 | 对应suspended disk/sweep配置；保留耦合能力条件、干足迹拒绝；remove+suspended拒绝 |
| schema2 stamp/wall/transfer | castle/wall/shovel配置；验证旧definition/template身份后复制参数、实际stroke/baseline/sample及**限制性授权** |
| 旧water policy/speed选择 | 只映射到已声明features/参数；water policy0–3及合法material plain/molded仍为数据，不能另选后端 |
| smooth/compact公开兼容函数 | redistribute/field_adjust + disk；旧无效amount字段不能变成沙量授权 |
| begin/end/cancel | 同队列control信封与所有权；已接纳END仍须排空 |
| drop_gravel及现有白沫 | 继续作为表现扩展工作/消费者，共享域完成态与生命周期；不是权威沙量原语，不得伪装volume来凑统一 |

旧格式的未知kind/shape/schema、非有限值、越界、坏旧hash、非法授权明确拒绝；不把未知种类当填沙。数据错误映射到既有invalid_command/invalid_input，代次到inactive_generation/stale_generation，模板身份到template_mismatch；队列、关闭和后端故障由T02准入映射，不由codec假造成功。旧存档的完整支持矩阵和来源身份策略在T01.3单独冻结，禁止只替换版本号/签名。

## 验证范围

2026-10-18 T03修正UEP-CTRL-001：控制结果可为NO_CHANGE或REJECTED，后者必须携带非零已知错误且无任何字段/coverage/触及/数量/预算变化；仍禁止APPLIED。原版本拒绝一切控制失败是codec遗漏。字节布局不变，原G1/G2按当时来源保留；当前`g3_control_protocol02`212项覆盖补充语义，真实基准/控制证据见[G3记录](../验收/G3_结果.md)和[笔画契约](笔画状态_v1.md)。

2026-10-18 G1最终联合门：`g1_wire_delivery10`203项、`g1_profile_delivery11`100项、`g1_configuration_delivery03`87项，共390项。机器描述增加native_control_bytes=128和fatal_flags_mask=63；命令/结果字段偏移不变。fatal flags16/32/63保留、未知64拒绝；真实运行的标志设置和GPU状态机仍由T02以后验证。配置/存档规则见[配置与存档 v1](配置与存档_v1.md)。下段为前阶段199项结果，保留历史。

当前`g1_wire_delivery07`：199项headless通过；`g1_profile_delivery08`：100项通过。包含int64大于2^53/MAX/负seed位型、拒绝float身份、64/65容量、坏magic/version/stride/长度/枚举/保留字/租约/域、whole-domain普通sweep、受限features、零授权、混合拒绝→成功revision链、coverage-only、账本与数值负例、fatal不产普通结果、水tick零编辑结果。attempt01编译失败及delivery05授权覆盖失败保留，当前修复未回写旧结果。

这些是数据/ABI证据，不是新GPU执行器、最后消费者释放、三入口迁移、视觉或成本验收。实际命令、源hash和原始结果在对应run-manifest.json；新GPU阶段接入后必须复用该布局并做真实设备测试。
