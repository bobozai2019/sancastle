# ADR：GPU编辑事务与水策略 v1

日期：2026-10-11。状态：accepted-for-candidate-validation；接口/判据冻结，不代表实现或验收通过。决策性质：Godot适配，不声称原作算法。依赖：T00基线与观测冻结、docs/knowledge/water_sand的frozen v1。

## 1. 沙迁移与事务

保持单元中心/capsule距离、`max(0.001,1-distance/radius)`权重、半径(0,4]、strength[0,1]、整段amount一次计费、挖沙最多四轮与EPS=1e-6m³。每轮开始固定剩余量与active_weight，活动格条件`sand*A>EPS`，行主序；不能边取边改当轮remaining。第一版全域dispatch，后续局部dispatch另作单因素。

GPU权重、实际delta与四轮小计采用固定行主序Kahan求和，不用浮点atomic。逐格仍写R32F。CPU现有double算术→R32F为参考；不是要求GPU直接调用CPU笔刷。迁移不处理smooth/compact：混合操作在当前revision完成并同步所需CPU字段后走旧路径，下一GPU事务读更新后的revision。

有序队列按(sim_tick,command_id)执行，一个域最多一个正在prepare/commit的事务，待排队容量64；满则backend_unavailable。ID/generation/revision/ticket均int64，shader用两个uint位模式，禁止float身份编码。CPU可预留多个排队place的名义amount×strength；未回执dig不能提前花费。available=max(0,settled-reserved)。place不足按旧`available+1e-6<request`整笔拒绝，不自动缩量。旧临界EPS允许最多1e-6m³数值借差，不成为可循环透支的信用；负available归零且记录临界量。仅settled>=0时允许一次临界EPS借差；settled<0禁止新的非零place。所有在途预留之和<=settled+EPS，连续多笔不能重复使用EPS。CPU double的available窄化为float32时向下舍入，不能向上制造库存。

名义请求与实际GPU体积分别记录。结算以实际delta为主，桶账户挖正/放负；请求→量化差单列roundoff audit，不能凭空记成外部源汇。若实际place超过available+EPS或实际量/分布超冻结预算，拒绝候选而不是clamp账本。零强度保留旧applied/footprint dirty行为，但场与账户逐位不变。

事务流程：

1. 校验有限值/公共schema、入队及预留；读取同generation/input_revision完成态。
2. prepare写独立GPU候选，原权威态不动；归约出实际量、错误旗标、dirty rect/mask。
3. GPU校验候选并执行条件commit，绑定generation/input_revision/ticket；失败原权威态逐位不变。提交后读回128字节receipt，最多一笔在途，重复/过期回执丢弃并审计。
4. receipt核对成功后恰好一次结算CPU桶账户、释放预留，然后发布该generation/output_revision完成态。等待期间不启动下一水tick/编辑，不允许旧CPU绝对patch覆盖GPU新沙。
5. **画面发布不得先于结算**：实验显示使用保存的上次完成态/独立发布纹理，候选计算及物理commit不会改正在显示的纹理；结算后再拷贝/绑定新完成态。回接正式材质时必须保持此界限，不以现有同RID纹理被提前写入冒充延后发布。
6. 碰撞在结算后按dirty mask请求32×32脏chunk及边缘邻chunk，不先整图回读。回读/替换带generation/revision；实际拾取、沙面/碰撞差及≤100ms另由T05测。

资源失败/退出：先停止新命令，invalidate generation，等待已有render/worker资源所有权返回后释放RID；取消/失败释放预留一次。旧回调不重结算，不把backend失败映射为applied。

## 2. 二进制布局 v1

little endian、std430、command/receipt各128 bytes（32×4，16byte stride对齐）。传输层实现：`scripts/simulation/edit_validation/edit_protocol.gd`。CPU envelope另存domain_id，GPU域实例天然限定domain；world Y不参与XZ footprint，CPU canonical命令仍保存完整Vector3。

### Command

| byte offset | 内容 |
|---:|---|
| 0/8/16/24/32 | int64 ticket_id/command_id/generation/sim_tick/input_revision |
| 40/44 | uint kind(remove=0,place=1)/shape(circle=0,swept=1) |
| 48/52/56/60 | float startX/startZ/endX/endZ，m |
| 64/68/72/76 | float radius/strength/amount_m3/cell_size_m |
| 80/84 | uint grid_size/policy(legacy=0,displacement=1,impulse=2,combined=3) |
| 88/92 | float legacy EPS/available_m3 |
| 96 | int64 seed |
| 104/108 | float dry_depth_m/signed_speed_m_s |
| 112–127 | 0保留 |

### Receipt

| byte offset | 内容 |
|---:|---|
| 0/8/16/24/32/40 | int64 ticket/command/generation/input_revision/output_revision/applied_tick |
| 48/52 | uint status(pending=0,applied=1,rejected=2)/error_code |
| 56/60 | float actual_sand_m3/nominal_sand_m3（非负搬运量，kind决定桶符号） |
| 64/68/72/76 | int dirty rectangle x/z/width/height |
| 80/84 | uint dirty_mask low/high；256²共8×8 chunks，64²低4位 |
| 88/92/96/100 | uint invalid_flags/clamp_count/edited_cells/capacity_status |
| 104/108 | float displaced/retained_water_m3 |
| 112/116 | float impulse X/Z积分(m³/s) |
| 120/124 | 0保留 |

error map：0 none，1 invalid_command，2 insufficient_sand，3 out_of_domain，4 stale_tick，5 inactive_generation，6 backend_unavailable，7 audit_failed（内部），8 displacement_capacity（内部）。invalid_flags位0非有限、1负场、2量超预算、3revision失效、4CFL超载；任何旗标非0不能作为正常applied发布。capacity_status=0未涉及/充足，1容量不足且留水。无障碍间值使用，obstacle>=0.5为阻塞。

## 3. 保存、撤销与恢复

复用CheckpointStore现有schema与严格恢复门，候选事务状态作为版本化sidecar。保存请求立即禁止新提交，等待所有已接受命令/回执结算至完成tick，再捕完整字段/视觉history/账本/高水位ID；pending/reservation在保存边界必须为0，否则保存失败，不能遗漏后继续成功。

undo热路径不用CPU全图读回；保留最多32笔GPU前态/有界差分，GPU历史额外上限64MiB，超限淘汰最旧快速记录，但原prefix命令/检查点保留可暂停重演。跨tick必须暂停，在隔离态从一致检查点重演所有applied/rejected结果，字段与账户配对后原子替换、递增generation；不能以“逆笔刷”代替undo。恢复后同输入全字段逐位配对，CPU/GPU迁移容差不替代strict resume门。

## 4. NUM-08新增水策略

legacy_depth v1保留编辑瞬间water/momentum不变。new策略为`conservative_displacement_v1`，只主动响应bed上升；挖沙water不补量。B/C/D/E从**完全相同的沙编辑后状态**起跑，C/E另保留编辑前bed与eta作为输入。编辑后的新bed不含压实密度改写。

连通性：编辑前h>0.001且obstacle<0.5的四邻湿格组件，固定索引顺序遍历；不穿障碍、不跨不同湿组件、MVP不通过干地把另一水池拼接进来。组件最多N²格，队列容量N²，遍历至队列空；溢出/未完成拒绝，不截断后假称完整。

每供体需求depth=`min(old_h,max(0,new_bed-old_bed))`；在old_eta以下的床高上升也可位移相应体积，20/80cm均已出12cm水时需求量相同合理。供体退出接纳集合。合法接纳格只在其旧湿组件中、非供体且非障碍；接纳上限eta=`component max(old_eta)+0.02m`，capacity=`max(0,eta_limit-new_bed-old_h)*A_eff`。0.02m为本项目候选位移容量预算，不是原作常数，也不要求水面无抬升。

按组件分别归约需求/容量。充足时分配需求到接纳格，按capacity比例、固定行主序归约，最后浮点残差在合法有余量格结算并记录。容量不足则按总capacity搬运，余水保留供体，`capacity_status=1`与retained_m3明确；不能跨组件、删水、伪造sink或无界扩大范围。1个组件1次分配、最多N²接纳残差查找，无反复随机搜索。未找到可容纳roundoff的合法格则audit_failed并保持原态。

悬沙随供体水比例搬运：remove_sediment=old_sediment×moved_h/old_h。供体qx/qz按同一比例减少，接纳动量加入所搬运水原速度对应的hu/hv；分配本身不额外注入速度。不含模板冲量的位移组记录由于干格清零及后续solver限速产生的动量损失。h<=0.001干格动量归零；不得吞悬沙，水变0时剩余可溶悬沙须随所有水移走。

## 5. 独立速度与组合

signed_speed_m_s冻结档位：0、+0.25、+0.5、-0.25 m/s。模板取单元中心到circle中心或swept最近点的单位径向向量，中心距离0取零；乘原brush weight及signed_speed。作用于最终h>0.001的footprint，`delta_q=h*delta_u`，水/沙/悬沙逐位不变。D使用legacy水，E在C完成态上加同一速度。正负模板只是Godot候选，不解释竞品的5。

新增后的总速度上限4m/s，采用向量限速，记录被移除的积分动量、动能与clamp_count；外部冲量积分Σdelta_q*A、输入/损失动能独立账目，不装成水/沙源汇。速度0不重写任何场。沿原30Hz+CFL、MAX_SUBSTEPS=64，不改变Hz、不关闭超载检查；超64拒绝候选输入并记录，后续子步负值/NaN=0。诊断固定子步另报，不能代替正式CFL。

## 6. 水响应与归因门（候选运行前冻结）

- W01在静水12cm、r0.75、20/80cm平顶已露出old_eta且容量充足时，**完成编辑事务后**供体每格h<=1e-4m；排水量必须在接纳同组件/真实出口找到，eps_edit_water内闭合。不能以5秒后慢慢排完代替这个门。
- W04容量不足可保留余水，但retained曲线和capacity_status必报，不能按W01成功。不连通池/障碍外水与悬沙不变。
- W00静水/干地/无编辑/0速度控制不造水、不造动量；W05携水悬沙与动量按上述公式核对，挖沙不补水。
- W06分别记录各档速度的峰值eta、局部残水、外部冲量、clamp/CFL及0–5秒曲线。无原作时间曲线，不设虚构秒级复刻门。C与D先独立通过数值/稳定门，才能验证E，最终选型以相同输入曲线及正式成本。
- 0–5秒样本固定模拟时间0、0.1、0.25、0.5、1、2、5；同时记录完成tick/墙钟。1/30秒量化的0.25s取第8tick=0.2666667s并明确实际时间，不能谎称精确0.25。

## 7. 数值预算 v1

u=2^-24为float32 unit roundoff；ULP32(x)=2^(floor(log2(abs(x)))-23)，零/次正规用2^-149。工具权重/归约Kahan、R32F存储，R16F compaction保持原值（dig/place不重写）。预算代码与布局同源在edit_protocol.gd，候选运行前冻结：

- eps_cell(before,after)=max(2e-7m,16×ULP32(max(abs(before),abs(after)))+16u×abs(after-before))。例如0.4→0.41为4.863739e-7m；8→8.01为1.526833e-5m。只用于CPU/GPU分布差，未影响格要求逐位不变。
- eps_reduction(n,sum_abs_delta_m3)=max(1e-8m³,(4u+2nu²)×sum_abs_delta_m3)，要求固定补偿归约；若换归约结构须新预算/版本，不能事后放宽。
- eps_edit_sand / eps_edit_water=max(1e-7m³,2AΣ_touched ULP32(max(abs(before),abs(after)))+eps_reduction)。用实际受影响格量化预算，不按巨大域总量百分比。
- GPU receipt actual与CPU double逐格实际delta差<=eps_reduction。nominal→实际场量化差<=eps_edit；桶+场+真实源汇闭合按eps_edit。连续序列以逐笔预算和记录roundoff做闭合，旧5分钟0.5%/1%上限继续适用。
- 负沙/负水、NaN、未解释源汇、旧回调生效、重复结算=0。dry threshold不允许通过删小水制造闭合损失。严格保存恢复仍逐位相等。

所有eps在候选运行前计算/保存在case manifest。超支持状态或预算溢出为audit_failed，不用不有限/巨大eps“通过”。参数极端案例仍验证拒绝后原态完整，而非默认排除测试。

## 8. 所有权、影响面与反证

主执行者串行修改。候选新增scripts/simulation/edit_validation、shaders/simulation/edit_validation和tests/edit_validation；原ToolCommandQueue/Domain/shader/default profile不改。共享最小扩展为既有reference_preview的solver工厂；T05如需增加GPU事务入口、延迟发布、碰撞小回读、保存边界，只在独立候选子类实现，若必须共享扩展须补diff/受影响分支回归，不默认切正式入口。

基线缺陷EV-001：旧Queue对NaN radius未做有限检查，contract_probe直接证实入队成功，未执行异常笔刷。候选前置有限值校验返回invalid_command；旧路径保留。这是显式健壮性修正，不冒称异常输入与旧路径完全等价。零强度旧applied且有dirty_cells但场/账本不变已被探针证实。

反证条件：四轮分布超预算、强度零漂移、实际搬量/库存闭合失败、容量足够仍沙帽留水、跨湿组件传量、混合工具陈旧覆盖、receipt前画面发布、恢复逐位差、成本失败都会拒绝对应Gate。最终允许结论“局部有效/完整成本失败、保留实验”，但不能据此删减T05/T06原范围或改旧RG4结果。

