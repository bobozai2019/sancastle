# ADR v1.39：材质阶段原生复制诊断

2026-10-11，仅T05候选诊断，默认关闭，不变更冻结账本、逐位重演标准与正式算法。

`--beach-material-stage-trace` 使用独立材质coupler，继承默认关闭split-list实现。原step/slope/commit shader、绑定和参数保留，在列表之间复制原生字段。每个子步记录revision/index与顺序编号，复制侵蚀后sand/rock/water/sediment/wetness/compaction/obstacle、step备用wetness/compaction、slope备用sand、commit当前sand。R32/R16/R8格式分别保留；输出bin是诊断GPU副本的异步读取结果。

诊断副本仅写入新建RID。全部异步回调完成后才能释放副本与solver；私有worker在读取完成后关闭，活动实例仍由原隔离发布保护。源资源不改写。配置签名包含material_stage_trace，防止与非诊断检查点混用。没有新增动态静态UI层级。

副本创建/复制、列表拆分与回读会改变时序、成本和资源压力。因此首差异只能称为“本次诊断配置下首个已记录阶段差异”；不代表默认运行的首个差异，不用于性能结论。原分支严格FAIL必须保留，即使复制观察版本偶然PASS，也不放行G4。

先比较同次主/worker对应阶段输入，后比较输出。相同完整slope输入及不同slope输出才能把该次差异定位到slope执行；before已不同则只能定位到更早阶段，不能据此宣称材质公式有误。主机常量相同不等于GPU实际消费相同。需要进一步实际绑定、native DXIL和消费常量证据才能判断执行原因。

复验入口：`tools/run_beach_recovery_probe.ps1 -Probe beach_replay_original_probe -MaterialStageTrace`。结果分析：`tools/analyze_beach_material_stages.py <evidence目录>`。不混用precise、额外barrier或早期完整复制开关后宣称单因素归因。

缩小复制范围：`-MaterialCommitOnly`只复制38个子步的提交后沙场，但保留相同split-list与revision/index元数据。`-MaterialCommitOnly -MaterialDetailSubstep 11`在同样38个提交后副本基础上，额外复制指定子步的before/step/slope输入输出。两个开关及详细子步序号均进入配置签名；不能将前一运行的首差异序号当作后一运行已证实的固定起点。
