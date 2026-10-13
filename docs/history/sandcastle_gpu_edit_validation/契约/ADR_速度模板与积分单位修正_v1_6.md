# ADR：速度模板与积分单位修正 v1.6

日期2026-10-11，速度候选运行前固定。EV-007：v1的积分动量单位标签错误，不是数值公式错误。

## 单位

momentum_x/z=hu/hv，单位m²/s；`Σdelta_q*A`的单位是**m⁴/s**（体积×速度），不是m³/s。原dry-loss与外部impulse标签及旧诊断报告写m³/s的地方均按此errata解释，原数据/FAIL不重写。流量穿一条边的hu×边宽才是m³/s。

动能按单位水密度记录：`0.5*Σh*|u|²*A`，单位m⁵/s²；乘实际ρ[kg/m³]得到J。候选不擅自引入水密度或伪造水/沙source。

128byte wire offset112/116和数值`Σdelta_q*A`不变。decode新增正确的impulse_x_m4_s/impulse_z_m4_s键，原impulse_x_m3_s/impulse_z_m3_s仅为弃用兼容别名，实际单位仍m⁴/s，不做数值转换。量预算表达式的数值系数不变，对momentum使用相应单位m⁴/s，逐格使用m²/s。新增探针记录显式unit，不把单位改名冒称重验了已存原始数据。

## B/C/D/E与模板

policy=0 legacy，1 displacement，2 velocity-only，3 displacement+velocity。D从同一沙完成态起跑，水/悬沙不位移；E先完成C，再加与D相同的速度模板。C/D分别通过后才运行E的验收。

沿v1：signed speed档位0、+0.25、+0.5、−0.25m/s，合法范围[−1,1]且有限；模板为单元中心到circle中心或swept最近点的单位径向向量×原brush weight×signed speed，中心距离0取零。只作用于当前footprint且最终h>0.001；当前窗口外不得读取陈旧sand scratch。

速度幅度独立于正strength的沙量缩放，不额外乘strength。沿v1“零强度不改场”的控制条款，strength=0时跳过速度；speed=0也完全跳过，不通过q/h再乘h重写原momentum。D的0速度四水字段必须与B逐位相同；E的0速度四水字段必须与C逐位相同。

作用格计算`u_raw=q_before/h+delta_u`，向量clip到4m/s，再写`q_after=h*u_after`。未作用格原值不变。4m/s是模板加入后的作用格上限，不改原流体子步的`max(1.5,3*sqrt(g*h))`限制或全域其他格。逐格CPU/GPU数值对照沿已有ULP表达式；另独立检查作用格速度≤4*(1+16u)，不以hu的绝对底噪掩盖速度越界。

记录raw输入积分动量、限速移除积分动量、actual q_after−q_before积分及clamp_count；input energy delta、clip removed energy、actual energy delta分别记录并核对。private GPU诊断回执可存这些标量；main回执映射actual impulse与clamp_count，其余量取证时额外读取，不占用/改写保留字。

新增能量诊断预算在速度候选运行前固定：`max(1e-7 m5/s2,32u*Σ_touched(abs(E_before)+abs(E_raw)+abs(E_after))+eps_reduction(n,Σabs(delta_E)))`，E是该格单位密度动能积分。32u覆盖速度归一化、向量clip、点积/相减与h比例的R32F舍入；固定行主序Kahan的归约项仍用v1表达式。它是新能量量纲的诊断门，不改水/沙/动量门；任何clip能量与实际账目差都记录，不用新水源汇抵消。

保持30Hz、COURANT=0.35、MAX_SUBSTEPS=64；candidate若需要>64子步则拒绝，不能只待下一tick才发现超载。热路径仍只回读main128byte，诊断全场读回不作成本PASS。
