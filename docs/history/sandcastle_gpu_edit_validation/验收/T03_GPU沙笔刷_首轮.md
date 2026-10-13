# T03 GPU沙笔刷首轮（G2未放行）

日期：2026-10-11。判定：256²全域GPU候选首轮冒烟对照通过；T03三个小目标仍进行中，完成计数不增加。没有水新策略或成本PASS。

## 实现与新证据

新增sand_prepare/reduce/apply/commit/publish五个shader及gpu_sand_editor.gd。prepare全域按单元中心/capsule计算权重；固定行主序Kahan归约，挖沙最多四轮，每轮固定remaining/active_weight；独立Cells SSBO候选、GPU量/有限值检查后才条件commit到两份sand。128byte Command/Receipt保留整数身份、dirty mask/rect、实际搬量与拒绝状态。当前只legacy_depth，不改water/momentum/sediment/compaction。

显示sand使用单独published_sand纹理；物理commit不改该显示纹理，CPU回执结算后才publish复制。主域一次在途，publish前禁止下一backend事务。迟到/重复回执绑定ticket/generation/revision，已结算/空pending忽略，不能再次增加库存。

证据：`evidence/20261011_014554_scenes/`，GPU main RD、GTX1050/D3D12、960×540可见窗口，5笔操作通过；10字段原始bin、CPU sand、128byte command/receipt、源hash manifest、实际SPIRV字节hash/大小、报告/截图/hash索引均保存。中间成功014243/014418保留。014554验证的是future-not-due前置拒绝修正前的同一due路径，后续完整矩阵会覆盖该拒绝。

| 操作 | CPU/GPU沙分布最大差 | 实际GPU搬量 m³ | 判定 |
|---|---:|---:|---|
| circle remove 0.01 | 0 | 0.00999999977648258 | applied |
| circle place 0.01 | 2.98023223876953e-8 m | 0.00999999791383743 | applied |
| circle remove strength=0 | 2.98023223876953e-8 m（累积旧差） | 0 | applied，当前笔无质量改变 |
| swept remove 0.015×0.5 | 2.98023223876953e-8 m | 0.00749999703839421 | applied |
| place 10（库存不足） | 累积旧差不变 | 0 | rejected/insufficient_sand |

每笔receipt actual与CPU double对原始GPU逐格delta归约符合eps_reduction；桶账户与CPU参考累计差最大1.8626454e-9m³，在预冻结预算内。其余9权威字段每笔逐位不变。五次重复回执均被忽略、桶不再变化；applied的settle_us<=publish_render_us。热路径上传Command128bytes+控制64bytes、只读回Receipt128bytes；大状态读回属于另行数值取证，不参与成本。

## 失败与修正

- 013648：辅助函数_set与Godot原生_set签名冲突；检测后终止该任务自己的失败进程，未停止已有编辑器，原日志保存。
- 013828/013851：sand_apply使用GLSL保留字active；编译失败，保留记录。改active_weight并重新导入，运行时读取各shader compile_error及实际SPIRV，未用空shader或版本强改绕过。
- 013952：CPU参考restore会递增generation，探针未重绑定导致CPU admission失败/结果为空，随后误索引触发超时；GPU第一笔原始receipt仍保存。修正探针generation并加admission失败守卫；circle不附无关end字段，swept才附终点。
- 编辑器import曾出现自身ShaderFile面板跨线程错误，不用import退出码作候选PASS；候选只以实际SPIRV compile_error为空及新可见运行的stderr无错误判定。

## 尚未完成的范围

首轮仅正常小笔/零强度/一次扫掠/一次库存不足。尚缺64²和256²半径0.25/0.75/4、薄沙四轮不足、边角/空footprint/退化线段、NaN/Inf与极端float32窄化、临界EPS库存、重复/过期ID/tick/generation、脏mask完整性、连续重叠/库存预留、GPU后旧smooth/compact版本回退，以及全域→局部dispatch单因素。同步lab executor只消费due命令；未来tick调度/真实输入/暂停恢复由后续整合实现，不冒称公共队列已迁完。

GPU实际动作耗时未测；串行全域Kahan reducer可能有成本问题，首轮不推断收益。保留冻结预算，按原矩阵验证后才能放行G2，随后再做水位移。
