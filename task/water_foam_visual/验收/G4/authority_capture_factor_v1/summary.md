# 中间检查点单因素复验

结论：严格权威隔离仍未通过。仅增加中间保存不足以消除差异；没有修改权威代码或容差，也没有恢复性能调优。原始证据在main/，离线量化在analysis.json。

该运行以同一start.sandue为起点，分别执行end_only和with_middle两组。每组为mode0、mode0、mode1三个重放，各执行相同填沙、30tick、挖沙、30tick。两组使用同一原始Codec.load快照读取实现、相同tick完成和编辑结束断言；唯一主动因素是中间保存调用。

进程退出1、未超时、源码前后无漂移。1003项检查中64项比较失败；准入、finish、end_requested空、每次tick恰好+1、runtime健康、释放和无孤儿检查均通过。64项包括4项control原字节比较，其唯一差异为u32 word2的恢复generation，属于预期身份差异，不单独作为物理失败。其余独立字段/历史比较仍失败。

| 原始组 | 旧/旧AA | 旧/新AB | sand最大绝对差 | water最大绝对差 |
|---|---|---|---:|---:|
| end_only | 不同 | 不同 | AA/AB均2.384185791e-7 | AA/AB均2.980232239e-8 |
| with_middle | 不同 | 不同 | AA1.192092896e-7 / AB2.384185791e-7 | AA/AB均5.960464478e-8 |

configuration、simulation、selection、wave_requests、wave_start_times、cohesion_yield_height_m、sim_tick和advanced_time_s均精确一致。动量、悬沙、flux的原始分量差及current/spare/history对比见analysis.json；相近量级不是接受标准。

with_middle的阶段比较：

| 已保存边界 | 旧/旧AA字段 | 旧/新AB字段 |
|---|---|---|
| restored | 精确 | 精确 |
| place_sand_0 | 精确 | 精确 |
| place_sand_1 | 精确 | 精确 |
| place_sand_30 | 不同 | 不同 |
| remove_sand_0 / 1 / 30 | 不同 | 不同 |

因此目前只能将首个实际分歧限定在填沙后的第2至30tick之间，不能声称已定位某一个tick或dispatch。place_sand_30的AA中sand仅2个分量不同（max5.960464478e-8），后续演算扩散到其他字段。该观察不支持“只是少推进一次tick”或“END尚未结束”的解释，也不支持“中间保存就是修复”。此前另一读法探针的精确结果作为其自身条件下的历史证据保留。

现有容差适用性核查见../existing_tolerance_audit.md：没有找到可直接接受本次逐格差异的既有非零标准。有界8文件只读源码审查见source_review.md，未确认根因，维持C0；不因未发现明显竞争就声称代码或引擎无问题。

后续若扩大数值调查范围，应取得最早分歧tick/dispatch的同源输入输出及匹配引擎资源依赖证据。该工作与权威修复不擅自并入本轮纯表现实现；当前不改物理、不增容差、不以此重开性能预算。
