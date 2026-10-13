# ADR：原生沙水共同事务 v1.5

日期2026-10-11。候选实现说明；继承v1–v1.4，不更改数值预算、容量或原沙分配规则。

`gpu_sand_editor`新增候选/提交/回滚钩子，默认legacy实现为空，policy=0。`gpu_water_editor`支持policy=0/1；unsupported policy在派发前拒绝。沙归约允许0/1，但未具备水扩展的backend仍不接收1，避免将未实现的水语义冒充成功。

water_prepare读取同current_index的GPU rock/sand/h/sediment/hu/hv/R8 obstacle，并直接读取沙candidate中的before/after。局部模式只在当前edit_window且正权重格读取candidate；窗口外使用物理沙面，避免复用上笔陈旧scratch。热路径没有CPU old-bed重建、全场读回或重新上传。

顺序：沙prepare/四轮归约→水prepare/候选/审计→合并同一128byte编辑回执→条件沙commit与水commit。水审计失败将main receipt置rejected/audit_failed、actual=0、output_revision=input、dirty metadata=0，因此两个commit都不写权威态。容量不足是合法留水而非审计失败，capacity_status/moved/retained进入既有回执字段。

水commit同时更新两套物理h/sediment/hu/hv。运输失败或已知身份失效走统一回滚：沙从candidate.before恢复，水四字段从water_input恢复，不推进revision或桶账户。只回读main receipt 128byte进行结算；额外water_receipt及全场读回属于探针取证，不是生产热路径。

sand与water各有独立显示纹理，CPU结算成功后同一render-thread发布调用复制两个完成态。该实验只显示sand/water，未宣称完整沙滩中其他依赖纹理的发布一致性已验。Lab busy互斥阻止推进tick/重置；正式调度器、外部backend调用和真实退出互斥仍归T05。

负例注入仅由测试属性设置一次：删除GPU候选水后原有量审计拒绝，无伪造sink；运输注入在两个commit之后、回执读取之前验证共同回滚。默认flags=0。失败backend只允许只读取证和release，探针不通过临时ready或清错误恢复运行。

025902原生12项通过；030109 legacy沙矩阵162项通过。具体范围/剩余项见验收报告；不以事务成功替代后续速度、真实交互、恢复和成本门。
