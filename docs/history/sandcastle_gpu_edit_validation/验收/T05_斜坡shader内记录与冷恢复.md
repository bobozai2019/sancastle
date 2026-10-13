# T05 斜坡 shader 内记录与冷恢复

2026-10-11。默认关闭的SlopeRecord诊断，为减少之前逐tick回读/复制的观察扰动，保留原材质三pass单compute list，只在slope shader内写私有65552字节记录buffer，全部七tick完成后统一读回。既有正常CFL/完成态回执仍在，不声称运行没有任何读回；报告mid_tick_readbacks=false仅表示没有新增记录数据的中途回读。

四个选中格为153745低取数失败中的25525/27334/28096/40900。每格最多128条、每条128字节，包含实际sand/next_sand、rock/wetness/compaction/obstacle、八个实际push参数、四邻格sand/rock/wetness/compaction。只观测这些格，不代表全域中间阶段。主机保存每次原dispatch的revision/index/delta_s及实际诊断SPIR-V hash。

记录buffer只在诊断版本增加；选型、性能和普通入口仍不用该buffer。configuration显式包含slope_record_requested，不能把诊断检查点误当非诊断配置恢复。诊断编译及额外写入仍可能改变寄存器分配、资源依赖或时序，结果不能冒称无扰动观察。

154449首次初始化FAIL、零项；修改诊断shader的GLSL保留字sample为record_index并增加编译错误输出后，重新自有headless导入，进程正常退出。原日志保留，不记为恢复失败或成功。

`evidence/20261011_154635_beach_edit_process_probe` writer 7/7 PASS，实际每格48次记录；tick17前34次，后14次。`evidence/20261011_154659_beach_edit_process_probe` 独立reader 9/9 PASS，每格14次记录。配对只把每条sample序号减去writer起点34，未改任何浮点字或物理字段；四格各14条32word全部逐位一致，metadata/revision/index/实际参数/诊断SPIR-V一致。保存态、七tick继续态、账本/prefix及画面也一致，原负例拒绝。原始记录与归一记录同时保存，解析索引见reader slope_record_alignment.json。

运行命令为run_beach_recovery_probe.ps1 -Probe beach_edit_process_probe -CheckpointMode write/read -SlopeRecord -CompensatedCapacity -PackedRuns -CachedCapacity -PrefetchVelocity，read来源对应writer目录。GTX1050/D3D12/1080p/VSync关闭，未启用StepReadbacks、材质阶段复制、shape复用或CPU采样。manifest及artifact_index保存源/引擎/参数/产物hash。

结论：shader内记录工具有效，当前诊断对照严格一致，但没有复现153745低取数原路径的四格ULP差异，不能覆盖原FAIL或宣称根因已解决。后续单因素应区分新增buffer依赖和shader编译变化，不在没有反证时认定同步或FMA。G4/76.2%保持，普通恢复严格门仍未过，撤销未执行。

## 只计数的单因素反证

新增默认关闭SlopeCounter模式：相同coupler、65552字节buffer、binding7、四个格及原三pass单list；shader仅对四个hits执行atomicAdd，不写浮点记录，也不增加邻格读取。配置显式记录counter_requested；运行器自动携带SlopeRecord和SlopeCounter旗标，不混用完整记录版检查点。记录报告counter_only=true，空浮点payload不是输入/输出一致证据，只验证计数及主机metadata。

155145 writer7/7 PASS；155212独立reader9项中仅full_edited_seven_tick_continuation FAIL，计数及metadata配对PASS。实际writer四格各48次、reader各14次，checkpoint当前字段/metadata/像素一致；继续后sand/bed_0八格不同，最大1.1920928955078125e-7，bed_1五格不同（最多5.960464477539063e-8），sediment格22111差1.7763568394002505e-15。具体格及最大差值见reader counter_only_difference.json。目标编译通过并终止，FAIL正常保留，没有因runner观察超时重启。

该运行反证“只添加这个buffer/atomic写依赖就足以消除严格差异”。完整记录通过而计数版失败，不能进一步直接认定浮点编译或同步原因：shader指令与额外读取仍不同。下一单因素是仅记录sand与next_sand，不额外读取邻格或物质输入；原严格门不放宽，G4/76.2%保持。

## 仅记录既有沙输入和结果

SlopeOutput默认关闭，和前一计数版相同四格、buffer、single compute list，在atomic计数外只把已计算的sand/next_sand以floatBitsToUint写入每条前两word。没有增加neighbor/wetness/compaction/rock读取，没有中途诊断取数。配置显式区分output_requested；metadata包括output_only，原始记录与归一记录保留。

155619 writer7/7 PASS、155707独立reader9/9 PASS；四格各14个继续子步的输入sand和next_sand逐位一致，metadata/参数/实际诊断SPIR-V一致，检查点、最终继续状态、账本/prefix和画面也一致。其余记录payload为空，不作为邻格输入证据；解析见reader slope_output_alignment.json。双方编译通过，正常退出，自有导入进程12204退出。

此组成功不需要完整记录版的额外邻格读取，但仍不能确认浮点结果写入是修复原因：原路径本就间歇通过，改写shader会改变编译和调度。计数版失败与本组通过分别保留，不替代原严格门。下一可检验候选是显式GPU结果存储并消费，保留公式和预算，并另验实际成本/全域结果/多次冷恢复；当前仅确立测试方向，尚无该候选完成证据。
