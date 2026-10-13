# ADR v1.38：完整原生输入复制与默认关闭对照

2026-10-11，诊断候选，不放行G4。

GPU复制记录扩展到当前10字段、spare8、foam/bed4和front共23字段。R32/R16/R8/RGBA32/RG32分别用原格式复制，最终统一异步读回，保留原始bin/hash，不经半精度再编码。--beach-copy-native-boundary采样7/8，--beach-copy-native-early采样0–8；均同时保留1–19沙完成态。它们改变复制负载和调度，不代表默认版本首差异。

两个独立默认关闭对照分别检验材质compute list拆分和沙累计浮点收缩。split_material_coupler保留原shader、公式和参数，只将step/slope/commit分成三个list；precise_material_coupler保留原dispatch，另加载只对next_sand增加precise的shader副本。原共享shader、耦合器和默认行为保持。配置签名记录split_material_lists/precise_slope，避免跨对照检查点混用。

原分支严格证明继续按23字段/index/五账本/prefix判定。当前两种对照均FAIL，不能作为修复采用，不根据这些负结果单独宣布排除了所有同步或浮点问题。
