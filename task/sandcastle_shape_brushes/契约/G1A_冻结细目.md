# G1A 基础冻结细目 v1

2026-10-15城堡行为已由[ADR-B26](../决策记录.md#adr-b26城堡固定世界标高低填高留)修订：固定世界Y基准0，低填高留、重复不叠高；取消区域最高点/0.25m落差门，obstacle格保留，城堡请求预算使用原48m³硬上限。当前规则见[几何与数值](几何与数值.md#3-城堡模板与放置)，验证见[固定标高专项](../验收/G5_固定标高放置.md)。下文相关原参数/公式保留作为冻结时历史，不再覆盖本次明确修订；其他布局、账户及刷子契约继续有效。

日期：2026-10-14。C01–C04/C06/C08为frozen v1，C07版本/配置/生命周期架构为frozen v1；C05材料规则、可能的native新增字段仍draft，G4定案。本文件补齐三份主题契约中的待定项，优先于其“拟定/计划起点”措辞。机器规范：[contract_v1.json](../../../tests/shape_brushes/contract_v1.json)。它是验证规范，运行代码不能加载tests/task；T02将显式实现相同规范，资源存assets/brushes。

## 预设和合法范围

| 工具 | 默认 | 范围 | 单命令有限权限 |
|---|---|---|---|
| 城堡 | 4×4m，scale=1，最高0.7m，yaw=0 | scale统一XZ 1–1.5（4–6m）；最高0.5–1.0m；yaw规范到[-π,π) | add≤48m³，transfer=0；按完整实际体积通过或拒绝 |
| 墙 | 高0.3m，底宽1m，顶宽0.5m | 高0.15–0.6m，底宽1–2m，顶宽0.5–1.5m且≤底宽 | add≤8m³/段，transfer=0 |
| 铲子 | 沟宽0.5m、深0.15m、每肩宽0.5m | 宽0.5–1m、深0.05–0.3m、每肩宽0.5–1m | transfer≤1m³/段，add=0，ridge高度≤baseline+0.5m |

城堡4m替代计划约3m初值，以保证墙厚/城垛宽及间隙0.5m至少4物理格。第一模板局部[-2,2]²，65²个RGBA32F样本、0.0625m间距，通道为normalized_height/foundation_mask/shape_mask/reserved(0)；height双线性，mask最近邻，越模板边界不写。四方塔中心(±1.25,±1.25)m，塔宽1.5m；墙厚0.5m；底座默认0.08m，围墙0.4m，塔顶平台0.55m，墙和塔楼城垛峰0.7m，所有高度随height/0.7缩放。塔楼四角0.5m城垛，中间0.5m开口；墙间连接至少0.5m。物理样本网格与原始生成参数/hash在T05一起保存，不能用画面细分替代。

城堡基底取完整foundation中实际bed最大值B，max−min≤0.25m；obstacle/完整模板越域/非有限均拒绝。所有foundation目标=B+Hscaled，当前较高bed只保留。由于B=max，当前foundation不可能高于B+非负H；旧高堆通过落差门拒绝，取消额外未定义的“关键轮廓阈值”。基础低处真实填实并计source，无削平/悬空/体积归一化。

MVP新工具默认policy=3、speed=0；旧工具policy/speed继续原配置。新工具允许合法policy0–3及speed[-1,1]作显式配置/对照，但MVP UI不另加水速控件。material_profile数值0=plain_sand_v1，1=molded_v1预留；G4前只接受0，G4冻结1的内容而不改变基础wire布局。参数必需且严格白名单，未知参数/非有限/布尔冒充数字均拒绝。高层资源ID对应operation唯一，hash校验真实文件；不能把任意文件路径或RID作为请求参数。

墙add_budget=min(8, (L×wb+πwb²/4)×(h+0.25))，L≤2m。0.25m为有限baseline修复余量，当前床因模拟降低得更多仍由实际体积预算完整拒绝，不能无限补回。城堡add_budget=min(48,(4×scale)²×(height+0.25))，最大全矩形上界45m³。铲子transfer_budget=min(1,depth×(2wL/3+πw²/8))，donor实际减量可少于该上界。CPU请求不得虚增权限；wire缩窄预算向下舍入，比较容差仅限量化预算，不能把eps作为额外权限。

## 路径及生命周期

采样间距0.125m（合法最小半宽/2仍≥该值），单段≤2m，每帧最多提交8命令；路径缓存256点，同域总pending64、唯一在途、至多一个活动stroke。保留≥1°的拐点和无效区子路径断点；小于1e-6m的移动视为静止。直线可合并到≤2m段，端尾在end时flush；normal end排完已接收缓存，cancel丢未提交缓存、已admitted命令drain。reset/close由原所有者cancel队列、等待在途终结，不能继续生成点。禁止覆盖最旧点伪装完整轨迹；超缓存显式stroke_buffer_full且停止该笔采样，已接受部分仍终结。

begin短暂取得原写者锁，基准由当时完整GPU rock+sand构造一次，baseline_token绑定stroke_id/generation，参数不可在该笔中途更换。基准复制完成前不采纳命令为可执行；失败释放token并不改变权威状态。基准/coverage生命周期为begin→draining完毕→释放，热路径不读取整图CPUshadow。保存/切换使用normal end+drain，恢复idle，无半条路径；相机/GUI/失焦/非法区/暂停的中断规则继续以[命令与交互](命令与交互.md)为准。

有效command_id用原域同一个单调计数；admission拒绝不消费id；已admitted后rejected/no_change均终结身份，重复不得执行/结算。sample_index在stroke内单调，从0开始；旧generation或重复sample无效。sim_tick入队不得早于完成tick，实际dispatch绑定最新完整revision，不使用入队时revision。baseline固定，不因每段执行或模拟重新建立。

## 256字节传输和回执

little endian，std430通过uint[64]访问；所有int64身份以相邻低/高u32保存，CPU用signed64，GPU用uvec2比较，不经过float。每字段准确offset/type见机器规范command_layout/receipt_layout，连续覆盖全部256字节，无别名/隐式padding。GPU不需int64扩展。请求magic=0x32535242（BRS2），回执magic=0x32535252（RRS2），version=2、stride=256；未知magic/version/长度/枚举/非零reserved或flags均拒绝。

| 范围 | 请求布局 | 回执布局 |
|---|---|---|
| 0–15 | magic/version/stride/operation各u32 | magic/version/stride/status各u32 |
| 16–79 | ticket、command、stroke、generation、tick、input_revision、baseline_token、seed各i64 | ticket、command、stroke、generation、input/output_revision、applied_tick、baseline_token各i64 |
| 80–95 | sample_index/grid/policy/material各u32 | error/sample/edited_cells/clamp_count各u32 |
| 96–119 | start.xz/end.xz/yaw/scale_x各f32 | dirty x/z/width/height各i32，两个u32 chunk mask |
| 120–151 | scale_z/height/bottom/top/trench/depth/shoulder/ridge各f32 | capacity/invalid各u32；added/removed/transferred/left/right/source各f32 |
| 152–183 | add/transfer budget、cell、speed、relief各f32，template width/height各u32，spacing f32 | sink/request/displaced/retained/water_error/impulse_x/z/sand_error各f32 |
| 184–215 | definition_sha256原始32bytes | eps_sand/water/transfer、nominal_add/cut、max_cell_delta各f32，reserved头8bytes |
| 216–247 | template_sha256原始32bytes（非城堡全0） | reserved |
| 248–255 | flags=0、reserved=0各u32 | reserved |

operation 1/2/3=stamp_target/wall_target/shovel_transfer；status 1/2/3=applied/no_change/rejected，与旧v1状态解码不同。成功output=input+1，no_change/rejected output=input；所有整数身份/实际tick必须与在途所有者匹配。rejected结果全部体积/冲量/dirty/eps结算项为0，错误可读；no_change体积/dirty/外部源汇0。传输失败没有可信结果，独立transport_error终结，不合成applied。capacity_status=0完整、1容量回缩、2零可接纳；铲子零接纳为no_change，预算/参数非法为rejected。错误枚举0–18与字符串固定见error_codes；collision_pending仅输入重试，不可当事务成功。

高层BrushCommand字段严格白名单采用[命令与交互](命令与交互.md)表，包括schema/domain/identities/operation/资源hash/坐标/各工具params/预算/水材料配置；非工具参数在wire显式写0，不从旧amount/strength猜值。输入参数与dispatch补充input_revision/ticket/grid/template元信息分开核验。BrushResult字段直接对应回执，dirty_chunks由mask展开0–63，单位只使用m³及m⁴/s。

## Shader资源与调用边界

所有新增compute stage在新目录；旧v1 pass不换wire/binding。prepare/allocate/validate/commit固定set0共享表，set1为实际solver纹理别名。push constant固定32bytes：8个u32=[grid_size,rect_x,rect_z,rect_w,rect_h,current_index,phase,reserved0]；workgroup16×16用于按格，归约每组256格，final merge按组固定序。

| set/binding | 对象 | 格式/布局 |
|---|---|---|
| 0/0 | command | SSBO 256bytes |
| 0/1 | receipt/control | SSBO 256bytes |
| 0/2 | cells | SSBO 64bytes/格：old/new sand、rock/water、qx/qz/sediment、old compaction/wetness/obstacle、baseline/desired bed、receiver weight、direction x/z各f32，flags u32 |
| 0/3 | reduction scratch | SSBO，256个block，每block 16个f32；最终control使用receipt，明确逐stage写/读 |
| 0/4 | baseline bed | image R32F 256²，只读当前笔 |
| 0/5、0/6 | coverage与candidate coverage | image RG32F 256²；x=desired bed，y=mask/历史donor编码，初始无覆盖；无身份float化 |
| 0/7 | template | image RGBA32F 65²；非模板stage可不声明/不绑定 |
| 1/0 | rock | 原完成态R32F |
| 1/1、1/2 | sand双槽 | 原solver双槽 |
| 1/3、1/4 | water双槽 | 原solver双槽 |
| 1/5、1/6 | sediment双槽 | 原solver双槽 |
| 1/7–1/10 | qx双槽、qz双槽 | 原solver双槽 |
| 1/11–1/14 | wetness双槽、compaction双槽 | 原solver R16F双槽；读取时转float32 |
| 1/15 | obstacle | 原完成态R8 UNORM |
| 1/16、1/17 | 可选support双槽 | 仅G4采用后定义，不在T02伪造存在 |

每stage只声明并绑定消费对象，不强制无用binding；water适配器可复用原私有water_input/candidate/scratch与原water pass set布局，桥接必须显式构造它实际消费的旧cell/receipt数据和完整positive delta。不得直接把v2字节给v1shader。water commit受同一v2validate控制，不能提前发布或独立结算；C05占位=保持原材料，未支持湿候选的框架测试只能在dry fixture上放行，不据此声称水整合完成。

T02修订（binding_revision=2）：已查实际gpu_shallow_solver初始化，wetness/compaction为R16F、obstacle为R8 UNORM，修正此前表格笼统标R32的错误；不改变原纹理格式、wire offset、物理语义或门槛。原G1A审计使用的spec字节快照保存在g1_contract_20261014_v3/frozen_spec_snapshot.json，原SHA256/报告不改判；后续运行规范与manifest使用修订后hash。

## 几何、分配和误差预算

T06工作区补充（ADR-B17）：不改变wire、cells和push布局。set0/3前4096个u32保持原归约布局，尾部增加32个u32临时空间；4096–4099为removed厚度和、removed tag厚度和、donor加权compaction、potential cut厚度和，供shovel分配/材料/最终核对消费，不进入检查点。原G1A数值门和历史结果不改。

T07输入/预览细目（ADR-B18）：城堡[ / ]旋转15°，不占Q/E；ghost共享模板H双线性/mask最近邻及同yaw/scale。shovel交互不按帧合并连续0.125m采样段，避免预算回缩/肩部水填充分配受事件提交时机影响；wall仍可合并，MAX_SEGMENT=2m和原冻结数值门不变。预览查询使用独立只读64byte摘要，不属于权威事务push布局或持久字段。

wall：到封闭线段的Euclidean距离d，a=wt/2，b=wb/2；F=1(d≤a)，F=(b−d)/(b−a)(a<d<b)，其余0，a=b时圆柱平顶。target=B+hF，同笔coverage max，不叠加；bed_candidate=max(current,target)。平床解析体积h[(wb+wt)L/2+π(wb²+wbwt+wt²)/12]，CPU独立积分与GPU格中心离散体积分别报告，离散场才用于账本。

shovel：同封闭线段距离d，r=w/2，trench F=max(0,1−(d/r)²)，target=max(rock,B−depthF)。donor d<r；receiver r≤d<r+shoulder，以dot(p−closest,n)符号分左右，中心线为donor、不作为receiver；端帽采用同距离。receiver权重sin(π(d−r)/shoulder)，容量max(0,B+0.5−current_bed)A，obstacle/历史donor都排除。每次新增donor并入该笔donor mask，后续receiver不能回填已开沟；新donor可覆盖先前肩部，这次实际挖量再守恒分配，不能丢弃先前沙。左右定义可随反向交换，等量规则不变。flat解析最大cut=depth[2wL/3+πw²/8]。

容量权重分配独立CPU参考使用bisection water filling：a_i=min(cap_i,λ×weight_i)，Σa_i=V，GPU可固定序饱和余量再分配。Vcut=min(actual_donor_capacity,transfer_budget,2Cleft,2Cright)，左右各Vcut/2。float32后重新归约removed、left/right、净Δsand；最多两轮按全域row-major格序修正残差，仍不闭合则完整拒绝，禁止外部源汇抵消。容量不足只能回缩完整搬运或no_change。

u=2^-24，U=max(|before|,|after|)，ulp32(U)按真实binary32指数（subnormal=2^-149）；eps_cell=max(2e-7,16ulp32(U)+16u|after−before|)。联合donor/receiver/材料以及water接收所有触及格包括值未变格，量化Q=Σ2ulp32(U)A；absolute_sum=Σ|Δfield|A。归约每256格使用补偿求和，再按block索引固定序补偿merge，R=max(1e-8,(8u+2(n+256)u²)absolute_sum)。E=max(1e-7,Q+R)，eps_sand=E，eps_transfer=2E（left/right各自float32归约及最终差），eps_water=对应water联合域的E。旧v1函数与因子保持原样；新factor8覆盖两级归约，不能因看到FAIL放宽。回执同时保留各体积、eps及max_cell_delta，CPU复验另存Q/R/n/absolute_sum。实际源汇由最终离散体积结算，不把analytic几何体积记账。

## 水、恢复及验收

新非零水速方向固定为正抬床delta的外向方向：wall为离最近中心线的单位向量（端帽同理），castle为−∇Hscaled归一化，shovel为肩部离沟中心线方向。flat/零梯度/仅降床区域冲量0；增益沿用合法speed×当前可用水深，不用沙转移方向代替水响应。speed=0不增加速度冲量；保守水位移可搬运已有动量/悬沙，必须区分“无新增冲量”和“逐格原动量不变”，闭域总量/总冲量另验。T08验证CFL和units，不降低原子步上限。

gpu_beach_edit v4当前未占用，冻结为新混合前缀版本：sand_accounting=external_v1、brush_schema=2，旧命令明确backend=legacy_v1/原预算，新增backend=brush_v2并记录definition/template hashes、预算、实际tick、v2结果及operation。新增操作只在external_v1形状授权场景启用，原库存场景新schema明确拒绝，原库存v2和external_v1 v3保持独立验证。完整native如无新材料仍v1；新增字段才native v2，G4列格式/双槽/恢复，不提前实现。配置签名增加scripts/sand/brushes、scripts/simulation/brushes、assets/brushes、shaders/simulation/brushes及f32/rgba32f/bin原始扩展与template manifest；既有scan保留。存档必须包含所有原raw/spare/历史及新材料，保存drain、无缓存持久化；错误载入原态不变。

验证矩阵[验证计划](../验证计划.md)全部冻结。输入外观门0.02m/1%不用于守恒，逐格CPU/GPU按eps_cell；MAT保形干态30模拟秒，每个塔楼与墙代表峰高≥80%、occupied IoU≥0.8。固定ROI为命令footprint+1m，occupied为相对原床新增高度≥该工具峰高的10%；四塔分别在模板四塔footprint内取peak，不只取整图最高点。细城垛独立观察。5分钟可见耦合长稳、两轮main/capture/backwash回到main、至少10次短切换保持原门槛。

G1A只验机器schema、预算解析参考和原账户CPU admission；G2才验GPU生命周期/框架，G3/G5/G6分别验真实形状，G4最终材料，G7真实UI，G8水/恢复/场景，G9最终长稳。未知first_visible/成本均标missing。未来runner接口/各组ROI、命令、P0用例以验证计划和本规范为准，不把未实现命令当测试结果。
