# ADR：旧 compact 的 R16 编码验证 v1.2

日期：2026-10-11。EV-004为观测假设错误，不是新GPU笔刷物理修正。v1.1曾以0.5 ULP16假定R16存储采用round-to-nearest；该假定在本机旧compact路径不成立，不能通过加大浮点容差掩盖。

原失败015841两域的compact各112格GPU值低于CPU Float32，最大差0.74169921875 ULP16。独立headless诊断按原Domain.compact产生Float32，再用Godot Image FORMAT_RF→FORMAT_RH编码，64²/256²编码bytes均与原GPU compaction **逐位相等**。诊断log、CPU原生R16 bin附于原失败目录，不改其FAIL。

此后混合旧compact对照采用同一原生R16编码的逐位相等门，原Float32数值仍可记录为解释信息。原gpu_shallow_solver.initialize本身使用这个Image转换路径，判断有现有实现依据。不能把本样本推广为所有硬件/格式的IEEE舍入性质。

该修改不放宽eps_cell、eps_edit_sand/water、归约门，不改变GPU任何数值公式，不改变dig/place后compaction逐位不变或严格恢复门。它替换了不适用的理论格式假设，并以原生格式逐位验证。reject回执的dirty rect/mask/count归零，仅收敛元数据到“没有权威改动”的约定。
