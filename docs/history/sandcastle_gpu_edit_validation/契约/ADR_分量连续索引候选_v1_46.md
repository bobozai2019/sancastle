# ADR v1.46：分量连续索引候选

2026-10-11。默认关闭的`--packed-runs`候选，继承v1.45 CAS湿段图与多分量处理，不改原shader或默认配置。

v1.45修正版完整场景候选pass约82–83ms、C/E反馈约163–169ms，仍FAIL。新候选只压缩每分量的格索引：逐行计数，经分量/行前缀得到互不重叠的区间；各行按x递增散射，因此每个分量列表严格为原row-major序。lane0 Kahan、残差逐格修正顺序、公式、预算、事务/库存及异常回退保持。

原5N个int scratch中，段0保留label，段1保存packed格索引，段2保存分量×行计数/前缀。新增shared starts32/cell_ids64及current_component，增加388byte，总shared<32KiB；没有增加GPU buffer分配。尺寸<=256、每行<=8湿段且分量<=min(32,size)才接纳，超界回退原BFS。SSBO阶段之间显式memoryBarrierBuffer+工作组barrier；所有padding lane为干格，禁止其写回。

各tile只读对应分量索引，Kahan输入顺序不变；接纳分配按格独立并行，残差/预算仍按原序累加。候选审计拒绝时清word27并交给原BFS复现原诊断。

必须先与原GPU及v1.45二进制配对（仅私有路径word27正规化，未发命令临时收据单列），保留原run_overflow64参考预算FAIL与天然缩采样64拒绝，再做完整负载GPU分段/反馈；尚未声明该候选正确或有收益，也不放行G4。

实测补充：124527与原GPU644语义bin逐位；125401的33分量上限回退4项PASS、94 raw bin相同。124743完整C/E候选pass约23.85/23.94ms，反馈C99.093/B72.591/D103.280/E103.716ms，D/E仍FAIL；只记录诊断窗口，不放行。见分量连续索引验收报告。
