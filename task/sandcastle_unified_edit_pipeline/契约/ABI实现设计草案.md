# ABI实现设计草案

2026-10-18：本草案已由[ABI v1](ABI_v1.md)及其机器表替代。以下512B候选中若有旧96/64B头、保留区或数量差异，仅作设计历史，不作为当前实施布局。

角色：design_draft。状态：待T01实现和负例验证，不是冻结契约，不计已完成小目标。当前G0矩阵运行期间仅整理源码可实施性，未创建运行数据模块、shader或profile资源。最终选择必须在T01依据资源容量、编码和故障测试核对。

## 统一表示

候选采用当前形状64B/cell的可复用字段，避免为每工具保留一套cells、material_transaction或water_transaction。当前prepare在每笔覆盖全域并清flags，成本须与G0比较；后续局部化必须有本次有效矩形/coverage并集和清除规则，不能读取上笔残留。材料候选使用目前空余word4–9，不再复制四份权威备份作为正常事务前提。

| cell word | 候选含义 | 使用边界 |
|---|---|---|
| 0/1 | old/new目标字段值 | bed/suspended由公共声明决定；非目标字段必须读权威完成态 |
| 2/3 | rock/current water | 床变化向公共水输入转换；悬沙操作不伪造床变化 |
| 4/5 | old/new compaction | 材料能力启用才验证/提交，R16F存储预算不变 |
| 6/7/8/9 | old tag/ref、new tag/ref | 原语输出几何，公共材料阶段维护候选 |
| 10/11 | stroke baseline/target height | fixed world与单笔baseline由字段明确区分 |
| 12/13/14 | weight/direction.x/direction.z | 搬运/动量模板辅助值，不授权权威写入 |
| 15 | touched/donor/left/right及invalid flags | 实际changed单独从old/new及材料对照计算；touched预算不能改changed-only |

公共水输入继续为每cell 32B（old/new床和水/悬沙/动量等），候选16B，拓扑scratch及已保留的displacement/velocity核复用。形状prepare不直接调用私有水事务：所有床候选通过同一桥接器进入公共阶段，所有结果经统一决定后提交。模拟tick保留既有数值算法，由统一域登记权限和完成发布。

分块归约需独立保存净沙量、removed、左右receiver、touched ULP预算/绝对变化、非法位、实际changed cell/tile、材料非法位、水/悬沙误差与预算项。先按固定行序分块补偿求和，再固定顺序合并；禁止浮点atomic决定搬运分布。原始公式容差沿protocol_v2和普通冻结契约，不借统一修改阈值。`water_merge`全域单invocation逐cell验证应被公共分块归约替代，不能仅删除检查。

## 命令布局候选：512B

一套固定stride代替当前128/256B运行分支。512×64+64=32832B/槽输入；3槽98496B（不含control、结果和scratch）。容量应由同一常量生成编码、上传、restore重建与故障注入边界。候选把CPU白名单profile快照编码为固定字段，GPU不解析工具ID和资源路径。

| 字节 | 候选字段 |
|---|---|
| 0–31 | magic/version/stride/operation/shape/destination/derived_field_mask/capability_bits，u32 |
| 32–79 | command_id/generation/stroke_id/baseline_token/sample_index/requested_tick，i64低高uint传输 |
| 80–95 | profile_version/water_policy/material_policy/control_kind，u32 |
| 96–127 | domain SHA256，CPU校验当前域；GPU可对control身份绑定核对 |
| 128–159 | effective profile SHA256，包含实际模板和覆盖参数身份 |
| 160–191 | template raw SHA256；不使用模板时必须全零 |
| 192–287 | 固定有单位float32：起终XZ、yaw、scale、radius、strength、height、宽度/深度/肩宽、amount、speed、datum等；未用字段规范化为零 |
| 288–319 | volume_sign/height_reference/target_rule/transfer_policy/stroke_policy及几何边界枚举，不允许任意阶段数组 |
| 320–351 | 固定输入范围或有界能力参数；实际范围和write_mask由公共注册表推导 |
| 352–511 | 版本1保留，必须为零；不能偷渡shader/执行器索引 |

操作原语和形状正交。begin/end/cancel使用同一信封中的有限control_kind，不把这些控制伪装为道具profile或权威沙变化。命令执行时输入revision/tick来自GPU完整control，不从CPU预测成功链。ID是正signed int64，极值拒绝继续分配，禁止float中转。

## 结果布局候选：384B/笔

批次每笔独立结果，批末80B完成通知可以保留为域完成外层，但必须升协议并显式指出统一结果数和stride；不允许通过总长度猜旧schema。64笔结果24576B，3槽73728B；具体读回策略和最后消费者证明纳入T02资源测试。

| 字节 | 候选字段 |
|---|---|
| 0–15 | magic/version/stride/outcome（applied/no_change/rejected） |
| 16–95 | command_id/generation/stroke_id/baseline/input_revision/output_revision/applied_tick/state_seq/batch_seq/lease_id，i64 |
| 96–111 | slot_id/changed_fields/error_code/completion_phase，u32 |
| 112–127 | dirty mask两word、changed/touched cell计数 |
| 128–191 | 增/减/搬运/两侧receiver/source/sink、沙水悬沙误差与量化预算等固定标量 |
| 192–207 | 实际变化矩形x/z/w/h |
| 208–271 | domain/effective profile SHA256 |
| 272–319 | 必要水/材料/ledger_precision/诊断标量；未用值归零 |
| 320–383 | 保留零；fatal/unknown不得编码为普通业务rejected |

公共提交是唯一推进编辑revision的地方；coverage-only no_change不推进权威revision。state_seq表示完整工作发布序列，可包含无沙变化控制/模拟工作；碰撞版本与GPU完成字段不合并。

## T01必须排除的失配

旧公开API只做数据适配；不能让schema1走普通执行器、schema2走shape执行器。普通估算ledger策略只能赋给原语/账户已允许的情况，守恒搬运保持source/sink精确不变。旧存档严格source signature拒绝仍有意义，显式迁移必须保留实际旧格式字段、来源和配置身份，不能只换版本号。

需要验证：坏stride/数组长度/尾部非零、未知操作×形状×目标、caller缩小write_mask、越界参数/NaN/float32编码溢出、非法模板hash、int64边界与命令顺序、profile资源改动后的排队快照、槽容量/restore rebuild同步，以及normal rejection后后继有效命令可继续。设计草案中的未定义字段不得成为隐式默认或占位成功。
