# T06-G02 六核双向原位读流与覆盖中断记录

角色：verification_evidence。证据批次：2026-10-26；整理日期：2026-10-27（Asia/Shanghai）。主执行者串行；没有并行agent。总体仍为6/8任务、25/32小目标、5/7 Gate；T06-G02进行中，G03／G04及T07未开始。本文补充[六核诊断历史](T06_kernel_diagnostics_20261025.md)，不覆盖旧失败、旧规则或旧Gate。

## 实际结果

| 范围 | 证据 | 判定 |
|---|---|---|
| 只读快照完整72身份 | t06_snapshot_godot_full_20261025_v3 | 216次完整打包输出逐位相同；已有结果，非本轮重跑 |
| 六核原生原位记录 → 原生及Godot固定流消费 | t06_readstream_six_20261026_v1 | 原生18份capture／18次replay；Godot54次对应消费，正常输出及完整stream精确相同 |
| 六核Godot自身原位记录 → 原生固定流消费 | t06_godot_readstream_six_20261026_v1 | Godot18份自身alias记录／原生18次反向消费，正常输出及完整stream精确相同 |
| 六核小样本独立审计 | t06_readstream_six_audit_20261026_v1/audit.json | 核原指令、真实输入、依赖、完成边界、全部字节配对，1562份artifact重算身份通过 |
| 完整72身份矩阵 | t06_readstream_full_20261026_v1 | 前47身份三阶段完成；第48身份只完成native，Godot链未闭；剩余24身份未启动。不接受全矩阵 |
| 已完成前47身份独立审计 | t06_readstream_prefix_audit_20261026_v1/audit.json | 仅已完成前缀，`completed_prefix_only=true`、`full_matrix_accepted=false`；不接受72身份覆盖 |

以上run均位于`docs/competitor/evidence/water_solver_reconstruction/`。完整索引及中断时源身份见[t06_progress_snapshot_20261026_v1](../../../docs/competitor/evidence/water_solver_reconstruction/t06_progress_snapshot_20261026_v1/progress.json)。前47身份的正常计数应为native capture141、native replay141、Godot固定流423、Godot自身alias141、native反向replay141；第48身份的部分数据不混入该计数。

## 方法、来源及适用范围

原capture SHA256为`761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2`；六核事件1484／1490／1495／1500／1537／1543的原program、ASM、CB及SRV由exact／fixture索引完整定位。设备GTX1050，原生D3D12，Godot4.7.2 Steam／Vulkan；512×256、32×32线程及原u0别名。正常输出固定2 MiB，床面／源汇每调用1个water load、stream4 MiB，另四核5个load、stream20 MiB。源汇与法线非零字节偏移已经逐load记录，原sand／RG16F纹理／air依赖不替换成water流。

capture保留原执行token子序列，仅新增2个temp和独立u1；单读／五读分别新增12／52条记录指令。replay仅替换water load的数据来源，独立重算原地址／偏移／掩码；Godot自身record没有只读stream输入，确实在单water buffer上读写。元数据及post-swizzle目的有效bits按调用／ordinal固定布局，未写lane补零。完整正常输出及stream均按原先零额外FP／quantization规则比较，不因结果调整容差。

三种已定位浮点表达式模型显式保留；早期`e*_inplace.glsl`仍未含模型，新生成`e*_inplace_record.glsl`才是本轮真实record来源。独立审计核验了原指令子序列、GPU实际水／CB／SRV／stream输入、正常输出和流hash、fence完成及submit-sync括号、SPIR-V及local device释放。

native每核5类守卫、Godot固定流4类守卫以及Godot record新3类守卫各有真实执行。全矩阵按相同build／adapter或probe／shader严格复用已有receipt，标记`reused_from`；不能称每个身份重新测过所有负例。损坏metadata而保留payload的控制说明只比较正常输出不足以验证记录。

## 执行命令与工具

完整矩阵原命令：

```text
python task/competitor_water_solver_evidence/tools/run_readstream_full.py --native-matrix D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t06_readstream_six_20261026_v1 --record-matrix D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t06_godot_readstream_six_20261026_v1 --build D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t06_readstream_executor_build_20261026_v3 --output D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t06_readstream_full_20261026_v1
```

矩阵模板准备始于2026-10-25T17:38:10.835610+00:00，即本地26日01:38；第47身份结束17:58:31.183217+00:00，第48身份native结束17:58:38.116583+00:00，即本地01:58。未补造父进程正常结束时间或第48身份Godot退出receipt。

前缀CPU审计命令：

```text
python task/competitor_water_solver_evidence/tools/audit_readstream_matrix.py --full-matrix D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t06_readstream_full_20261026_v1 --completed-prefix --output D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t06_readstream_prefix_audit_20261026_v1
```

该选项严格要求原请求72个唯一身份、已完成身份为请求的连续前缀、ordinal一致，只审passed三阶段子链；不把running父manifest转换成通过。CPU审计设`PYTHONDONTWRITEBYTECODE=1`，TEMP／TMP明确指向项目内`test_output/water_solver_document_audit_temp/`；必要审计证据保存正式目录。原始数据只读，未移动、删除或重写。

## 中断与新写入边界

用户本轮替换AGENTS，新增禁止向项目外写入任何日志、缓存、临时文件等铁律。检查现有launcher仅显式指定项目内`--log-file`，独立project.godot没有用户数据路径隔离配置，也没有完整TEMP／TMP／用户缓存重定向。不能据此保证后续Godot调用符合新边界。

因此执行`taskkill /PID 18716 /T /F`，仅终止本任务完整矩阵python及其子进程（回执含14108／17704）；句柄56897实际退出码1。未终止既有用户主项目Godot进程。父manifest与第48身份Godot manifest原样保留`running/not_evaluated`，以独立progress收口说明其已中断，不能误读为仍在后台执行。没有数值错误触发此次中断，也不据此宣称写入隔离已验证。

后续执行前先完成项目内TEMP／TMP、用户数据、Godot及驱动可控缓存、日志的路径配置与小样本写入审计，检查所有实际目标和祖先路径无外部联接；不能保证边界的工具不得执行。不得清理项目外历史文件或重用旧launcher直接补跑。已完成结果保持，补剩余覆盖用新run与新源码身份。

## 未关闭范围和可信度

C3：所索引插桩执行的真实输入、输出与读取流字节对应。C2：这些语义读取值能解释所测差异。额外UAV写入、寄存器分配及编译重排可能改变原位调度；初态／完成态值分类不是加载时间、原子性或全局合法顺序证明。原经验v1／v2无法覆盖独立原输出的反证不变。

T06-G02仍需剩余完整夹具及分支覆盖核对；G03须按真实阶段／参数轨迹做短序列，原位与显式ping-pong分列、逐阶段保存误差；G04须验证暂停／恢复／重置、generation完成态、资源及隔离边界。T07规格、归档复验、未知与最终ready／bounded／insufficient判定仍未开始。C03更新至v1.5只登记证据和覆盖边界，C04／C05正文保持不变。

竞品技术结论已整合[水求解参考与同步](../../../docs/competitor/水求解参考与同步.md#water-readstream-01六核原位读取记录与双向算术配对)及统一README；进度以执行状态主表为准。
