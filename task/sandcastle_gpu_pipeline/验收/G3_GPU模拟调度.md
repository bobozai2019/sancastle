# G3 GPU 模拟调度

日期：2026-10-17。结果：通过候选后端 Gate（P03），main frame pump/UI/生命周期接线仍归 P05–P07。

## 水核阶段

机器证据：[normalized.json](../../../test_output/gpu_pipeline/g3_20261017_01/normalized.json)、[normalized.log](../../../test_output/gpu_pipeline/g3_20261017_01/normalized.log)，80项通过。相同Steam4.7.2/D3D12/GTX1050、可见窗口，独立候选 solver，原 main 暂停且没有改运行接线。

实现：async_cfl_tiles 校验有限/非负深度与动量并产生tile最大速度；async_cfl_decide 单工作组完整归约，写64B决策及64×12B间接参数。CPU只录制64组有界阶段，GPU选取实际N，inactive x=0。drain/update变体只将已有ratio读取替换为GPU参数，原shader和旧路径ABI保留。

覆盖N=1/2/3/64、需求N=100、动量NaN。N=100按安全dt缩短actual_dt，完成时钟只按actual_dt推进；NaN得到status=2、N=0，不推进sim_tick且六份水/动量纹理原字节不变。正常各N归一到slot0，与相同初始化/实际dt/N的旧CPU调度水核最终水/双动量逐字节相同。测试读取决策仅用于断言，候选录制链没有CFL读回求N或CPU continuation。

G3-D01：首版将归一shader的Decision声明为只读，N=1/3的slot0仍保留前一子步，N=2/64正确；原失败 core.json、odd_diagnostic.json、日志保留。通过增加槽归一阶段的GPU所有权写入（Decision为read/write，归一时active_slot=0），最终normalized运行全部80项通过。没有调整公式/步数或放宽精度。原始失败的引擎内部原因尚未单独取证；只记录本机观察和已验证实现，不推广为所有后端缺陷。

命令：引擎 `--path D:/godot/project/sandcastle --script res://tests/integration/async_pipeline_water_probe.gd -- --output=res://test_output/gpu_pipeline/g3_20261017_01/normalized.json`，以--log-file另存日志。解析失败也保留；首次探针遗漏既有connected_runs配置产生uniform错误，后续已复制main有效配置。

## 关联模块、潮汐、表现与交错

最终证据：[full_interleave.json](../../../test_output/gpu_pipeline/g3_20261017_01/full_interleave.json)、[full_ordinary.json](../../../test_output/gpu_pipeline/g3_20261017_01/full_ordinary.json)，两轮各155项通过；对应同名.log无SCRIPT ERROR/ERROR/false。[manifest](../../../test_output/gpu_pipeline/g3_20261017_01/manifest.json)记录实际源码和命令。主场景仍不切新模式，测试候选使用main同源参数/资源。

- P03.1：GPU有效性/CFL归约及64组间接选择，N=1/2/3/64/超限/非法均通过；没有固定子步替代或CFL读回准入门。
- P03.2：实际dt、revision、sim_tick和advanced_time由GPU推进；水/材料/通量归一到已知slot0。无效阶段不写状态，非法CFL不推进时钟；奇偶与上限对照通过。
- P03.3：async_coupled沿用现有侵蚀、湿度、压实、ordinary/molded坡面、支撑算法，只将动态dt/指数分数改为GPU读取；async_boundary从实际GPU时钟采潮汐与波包，在GPU累计源汇；async_visuals用同一个actual_dt推进main当前启用的泡沫和碎石，结束稳定历史槽。main明确禁用的rise/local/contact字段未新增或启用。
- P03.4：完整有/无材料对照与非法CFL原始字段不变通过；三槽中同时提交真实编辑2笔/水工作/真实编辑2笔，在任一CPU消费前全部排入，水sim_tick确增1、末批revision再增2，实际时钟只在水工作推进。资源排空释放正常，无CPU CFL或潮汐往返。

水核对照为逐字节；关联动态GPU exp与原CPU double exp窄化允许事先固定的float32场1e-6、半精度场1 ULP单位尺度(0.0009765625)容差，最终有材料差异最大约2.98e-8。G3-D02：首版小dt直接float32 `1-exp(-x)`消减导致64步沙差1.4e-6，未放宽容差；改为同公式六阶小量展开（x<.1，截断<2e-11），重跑通过。coupled_mold失败和coupled_stable通过原始结果均保留。

G3-D03：变体uniform set依赖材料support_flags，须在material.release前释放water/variant sets；初轮释放次序产生invalid RID，已修复次序并最终日志复验无错误。G3-D04：测试恢复初始泡沫需要COPY_TO；仅对探针私有泡沫纹理增此标志，main资源格式保持原样。首轮full日志保留，最终full_interleave/full_ordinary无错误。

复验命令：水核命令增加 `--coupled --mold --boundary --visuals`，ordinary轮移除`--mold`，各轮用独立--output和--log-file。GPU源汇/视觉扩展只保留状态与小日志，未导出完整场到磁盘。

适用边界：GPU候选后端可串行完成编辑/水/关联模拟/当前启用的视觉历史，不声明main自动帧调度、碰撞、保存或三入口已通过。main表现材质时钟接线及持续用户输入的frame pump在P05完成，G3候选交错证据不替代G5/G7。
