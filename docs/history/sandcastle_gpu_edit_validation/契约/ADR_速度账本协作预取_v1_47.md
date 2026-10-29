# ADR v1.47：速度账本协作预取候选

2026-10-11，默认关闭`--prefetch-velocity`。只替换water_velocity_reduce的读取方式，接口/dispatch数/回执/公式不变，原shader保留。与packed-runs开关独立，可做单变量对照。

64线程读取一块64格的候选值与原/未裁速度至shared tile，工作组barrier后只由lane0按原格序执行Kahan动量与能量累计、最大信号和CFL64边界；不改树归约、精度或预算。增加shared2048+4byte，不增加GPU分配/CPU读回。尾部padding不参与累计。

非法候选仍按row-major找到首个非法格并写原error4；lane0置shared bad后全工作组经barrier一致返回，防止局部return留下其他线程。已有status非applied的收据直接保持。能量及CFL拒绝条件原样保留。

先D/E四速度、干/限幅/扫掠/退化/零控制、原CPU参考与GPU逐位对照，以及NaN/Inf/范围/CFL64负例，再与v1.46组合做完整场景反馈。未验之前不切默认，旧数值/冷恢复失败仍保留。

取证：D56/E56/常规负例20/直接GPU候选故障8均PASS，5562原始bin SHA逐位一致。131524 profiling与131921非profiling的完整四策略反馈均<100ms，但暂停事务窗口/实际首可见/连续输入与G4仍未完整验收。见速度账本预取与工作组拒绝边界报告。
