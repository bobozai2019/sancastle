# ADR：CFL64边界等价计算 v1.8

日期2026-10-11。EV-009，修正候选float32中间舍入，不改30Hz、COURANT=.35或MAX_SUBSTEPS=64。

035006两域各一例失败：实际原native CFL tile与candidate max_signal都为84m/s，现有CPU `substeps_from_cfl`要求64，candidate的`ceil((1/30)*signal/(.35*cell_size))`得到65而误拒绝。83.9999771m/s→64、84.0000153m/s→65和约1000m/s→762均有相邻反证，原20项JSON/原始cfl、command、receipt和状态保留。

改用等价式`ceil(signal/(30*.35*cell_size))`，冻结cell=.125m时分母1.3125可被float32精确表示。用precise保留分母组合顺序；不减epsilon、不扩大64上限，也不强改结果为64。超过uint范围的诊断steps用UINT_MAX标记，避免未定义浮点转整数。

035348原20项全部通过：host与GPU分别拒绝NaN/Inf/>1速度，84边界接受64，真正65/762拒绝且所有权威/显示字段、库存、revision逐位不变。高signal样本是人工分类器运输测试，不声称正常完成态允许这些巨大流速或已经模拟了对应时间。

该边界验证针对已冻结30Hz/.125m以及实际native signal，不推广到未纳入任务的任意网格尺度或Hz。后续新profile须重验其尺度边界，不改本任务语义去适应异常输入。
