# ADR：touched-cell 量化预算实现修正 v1.3

日期2026-10-11。EV-005。修正候选实现与冻结公式不一致，不修改ADR v1第7节的系数、上限或物理语义。

冻结公式的量化项是`2*A*Σ_touched ULP32(max(abs(before),abs(after)))`。笔刷有正权重的格参与放沙，即使增量小于R32F半个ULP而舍入回before，也产生量化误差；只统计before!=after会漏掉该项。

原023056微小量矩阵48项中10项CPU applied而GPU audit_failed。典型8m沙、r4、1e-5m³放沙被分配到很多格，每格R32F不变；旧实现quant=0、预算1e-7，错误拒绝。原commands/wire/receipt/CPU和GPU沙bin与失败JSON保留，后补artifact_index只建立hash索引，不改结果。

现在GPU归约对每个weight>0格累计quant和归约项数；CPU预算helper接受显式footprint，保留changed_count供解释。CPU测试使用旧Domain结果dirty_cells作为footprint；超出footprint的变化另由逐位不变门拒绝，不能用预算隐藏域外改动。默认未提供footprint时helper仍仅能推得changed集合，不能用于审计不可见的未改变加量格。

023241 codec/公式探针17项通过，含128个8m未改变格的精确预算恒等式。023247全域/023438局部微小量48项均通过；023317全域/023355局部常规162项均通过；666份bin逐位一致。实际量回执仍按GPU真正delta，舍入差单列预算，不向场或桶伪造外部source/sink。

023247启动器scope标签表达式出现SwitchParameter→int转换错误；数值进程正常完成，manifest的实际参数/hash及矩阵结果仍保存。后续启动器已改为显式分支；023438等标签正常。该观测错误不视作数值失败，也不修改原manifest冒称当时标签成功。
