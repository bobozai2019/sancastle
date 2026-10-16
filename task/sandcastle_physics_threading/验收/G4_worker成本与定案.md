# G4 worker成本与定案（进行中）

2026-10-14，主执行者 /root。T04 G01/G02完成；G03/G04待完成，G4未通过。生产默认baseline、独立物理线程关闭，未改project.godot/profile。

## 分块成本与临时候选

证据：`test_output/physics_threading/t04_prepare_visible/`，379/379检查、375份原始样本（1/4/16块×5模式×25次），每组交错反转执行顺序。1920×1080、VSync关闭、完整main波浪80/侵蚀开启，另置远离沙滩的碰撞fixture，不修改权威字段。进程正常退出、源未变。CPU准备、形状提交、墙钟分列；worker原始线程身份和每槽起止时间均保留，墙钟包含等待下一process_frame收集。

下表为完整apply CPU p95 / 调用至发布墙钟p95，单位ms；完整apply包含形状提交，不能称纯准备收益。

| 块数 | baseline | serial job | worker1 | worker2 | worker4 |
|---|---|---|---|---|---|
| 1 | 0.308 / 0.335 | 0.509 / 0.569 | 0.520 / 44.975 | 1.110 / 44.706 | 0.494 / 35.401 |
| 4 | 1.045 / 1.104 | 1.466 / 1.534 | 0.700 / 26.179 | 1.129 / 26.180 | 0.705 / 26.216 |
| 16 | 4.677 / 4.750 | 5.261 / 5.507 | 4.271 / 59.859 | 3.588 / 36.064 | 3.682 / 35.775 |

临时候选B：仅完整16块批次使用worker2，1–15块回到原baseline。只直接测过1/4/16，不宣称5–15块的最佳转折点已知。worker4无可证明的额外优势；有效并发受引擎线程池影响，不将请求4任务数视为4核同时执行。队列仍1活动+4等待，预算2MiB，失败/背压/回收契约不变。

随后把入口元数据检查计入candidate admission与baseline apply计时，并新增默认关闭、最多256份的成本样本；上述微基准是改动前计时边界，不与新短运行绝对值混算。旧数据及源码hash保持原样。功能证据 `t04_threshold_v2/`：22/22，1/4/15块立即baseline、16块实际worker，字节一致、一次完成、按实际路径记录、全部任务回收，exit0/source_changes空。

## 测量链路短验

`t04_short_A/`、`t04_short_B/`：真实main输入、固定同一origin，十字段/账本/prefix/tick初态完全一致；exit0、released true、source_changes空。监测只观察到原编辑器PID3192，无外部游戏进程。实际每笔准入、terminal、碰撞/两physics_frame阶段和最终十字段均归档。脚本每次调用均单独记录，统计不以128项环形历史长度代替命令数。

| 模式 | idle prepare p95 us | 连挖prepare p95 us | 连挖tick/s | 连挖frame p99 ms | 连挖调用/准入/terminal |
|---|---:|---:|---:|---:|---|
| A | 2315 | 2057 | 10.732 | 57.959 | 100/99/99 |
| B | 568 | 752 | 9.630 | 49.390 | 100/95/95 |

短窗口30秒只能证明链路可用。准备CPU降低但吞吐未达15，暂停反馈仍有约600ms尾部，不批准候选。暂停挖/填调用各20；A准入20/19，B19/19，全部准入有终态。差异不能忽略，正式比较同时报告尝试/准入/完成和实际命令prefix。

逐帧JSONL流式写盘，每批成本独立收集；GPU时间戳每100ms采样，不当全量GPU耗时。frame_post_draw只是提交观察，不是扫描显示。Windows过程CPU/RSS/线程数及NVML GPU利用率/频率/温度1秒采样；未采集主线程CPU单独计数，未取得显示扫描时间，不用缺测值填零。

## 正式窗口

冻结运行副本 `D:/godot/physics_threading_runs/20261014_cost_frozen`，11907文件固化期间hash无变化，清单 `t04_source/frozen_manifest.json`。原T00冻结副本保留。正式runtime身份再于每次启动/结束校验。

执行 `tools/physics_threading/run_pairs.py`：三对300秒，顺序AB/BA/AB，共同短验A origin，固定全部消费配置；启动前连续6次5秒采样无其他游戏进程，编辑器3192保持。运行中出现外部游戏进程的尝试保存原始结果并标记load_validity，不进入正式收益判断，最多3次后报告限制。1秒监测无法排除不足1秒的外部负载，判定保留该适用范围。

状态实时记录 `test_output/physics_threading/t04_formal_status.json`。本报告待回填三对实际结果、GPU长帧对应关系和G4选择；当前未累计正式窗口或Gate通过。

## 短测阶段分析补充

`tools/physics_threading/analyze_cost.py`由原始JSONL导出两份`stage_analysis.json`，记录脚本hash。GPU仅在同一captured frame内配对开始/结束，CPU只计算同command阶段墙钟，不跨GPU/CPU钟源相减。

短测dig_live中A/B采样碰撞GPU pack分别109/101对，p95为0.024576/0.028672ms、最大0.122880/0.130048ms。它们只支持“采到的pack纯计算很小”，无法排除未采到的异常帧、GPU全队列等待或驱动阻塞。A/B publication_ready→collision_ready墙钟p95为74.553/599.605ms、最大671.316/704.856ms；该墙钟包含读回、调度、准备、跨帧收集等，不归为某单项纯CPU成本。

长帧按monotonic frame interval关联该CPU区间内的碰撞callback，分别保存帧tick/pending/busy、callback数量及apply/readback最大值；不存在callback时为null。相关性不等于因果，未取得线程栈/队列证据前根因仍unknown。正式窗口完成后使用同一分析脚本回填，短测不代替G4收益门。

## 首个正式A窗口（非配对结论）

`t04_formal_P1_A_attempt1`已完成：exit0、released、source_changes空、无外部游戏负载，363.175秒完整进程（含初始化、暂停用例、300秒连挖、导出）。dig_live完成吞吐9.256tick/s，frame p99=63.959ms，1000次输入尝试/982准入/982终态；两项对应硬门未通过。连挖33个>100ms长帧，具体区间与callback关联保存在stage_analysis。采到的1014对GPU collision pack p95=0.029696ms、max=0.142336ms；publication_ready→collision_ready墙钟p99=618.187ms、max=713.069ms，等待来源仍unknown。

B已由串行runner启动，尚无完整配对结果。`compare_pairs.py`统一重新分析三对有效窗口，保留初态一致性、除候选开关以外配置一致性、退出/source/released、终态字段/prefix/tick差异，并按冻结case噪声逐对判定；不足三对全部三对收益项为false。短测实数据用于检查该统计规则，`t04_short_validation_comparison.json`明确diagnostic_only，不混入正式对数。

## 受污染B的线程CPU补采（不作为正式成本）

B attempt1运行时确认有外部4.6.2 Godot进程8888、随后8708。另用`thread_cpu_probe.py`对自有PID9120采10份1秒间隔线程数据，原始数据、源快照/hash、实际二进制路径与进程创建时间在`t04_thread_cpu_contaminated_B/`。工具先核对live_process记录的PID、image、创建时间，仅读取，不挂起线程。CPU使用[GetThreadTimes](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getthreadtimes)的kernel+user累计值；名字来自[GetThreadDescription](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getthreaddescription)，空名不猜主线程。

10份记录中线程6616（无名字）的CPU累计增量2,296,875us、12148（无名字）15,625us，其他观测线程增量为0；这是该短污染时段的直接事实，受CPU计时量化、线程退出和采样区间限制。它没有提供函数栈、等待原因，也不能证明worker无执行或identify主线程，根因仍unknown。

观察器单轮墙钟最大77,545us（含被抢占）；原始旧键`observer_cpu_wall_us`实际只测墙钟，不能冒称CPU耗时。该版本源快照保留，随后工具键改名`observer_wall_us`。补采只发生在已受外部负载污染的B attempt1，不追加到后续正式窗口，不能和A进行正式成本比较。

B attempt1最终exit0、released、source_changes空，但`load_validity.json`记录外部Godot PID7444/8708/8888，load_clear=false。该受污染窗口连挖4.390tick/s、frame p99=73.032ms、970准入/970终态，只作为失败/污染记录，不能当成worker造成退化的证据。P1 B attempt2在连续quiet确认后启动，自有Godot PID13384；没有重新启动或覆盖attempt1数据，仍等待完整有效三对。

P1 B attempt2运行中遥测又捕获外部Godot PID9068，该尝试也不能用于正式配对。已向用户询问安排约40分钟独占GPU测量时间，或继续自然等待/明确授权协调相关聊天；未授权关闭或联系其他任务。当前串行runner仍按既定quiet检查及最多3次尝试推进，没有因观察超时重启进程。

诊断关闭对照入口`cost_probe_no_diagnostics.gd`已编译通过，证据`t04_no_diagnostics_compile/`。该继承入口关闭GPU时间戳、详细碰撞成本和阶段诊断，只保留帧/真实输入/终态观察；编译不等于实际关闭对照已测。未将新脚本复制进正在测量的冻结副本，以免改动运行身份。正式配对后仍需执行关闭对照，量化诊断开销。

## 阻塞审计与恢复入口

第三次B运行约52秒时遥测记录外部Godot PID21324，仍无正式配对。此前两次同类阻塞分别发生于连续goal轮次，第三轮再次直接验证。确认自有PID12728的完整可执行路径和attempt3/冻结目录命令后，仅停止该无效自有探针；session71068以exit1结束，子进程exit4294967295、source_changes空，partial JSONL、日志、初态和启动身份已归档。强制结束不是正常released PASS，完整trace/final checkpoint缺失，`load_validity.json`明确completed_window=false。

当前自有runner/probe已终止。外部进程不关闭，其他聊天未发送消息；只读状态核对仍有另一活跃goal在执行900tick相关验证。三个已确认污染尝试及待测项见`t04_external_load_blocked_audit.json`。G4未通过，T04为2/4，整体18/32；T05–T07依赖保持，不将污染窗口算收益，也不改噪声或硬门。

用户的独占GPU时间/自然等待/明确聊天协调授权问题仍待回复。约40分钟无其他GPU游戏探针后，以新prefix重新取得完整AB/BA/AB，不覆盖原run；旧首A仅保留为独立基线，新的正式配对重新启动A。恢复前重核冻结源hash、实际引擎、profile、origin十字段及外部负载。示例入口（仅独占条件成立后执行）：

```powershell
python tools/physics_threading/run_pairs.py --project D:/godot/physics_threading_runs/20261014_cost_frozen --archive D:/godot/project/sandcastle/test_output/physics_threading --origin=res://test_output/physics_threading/t04_short_A/origin.scgpu --prefix t04_exclusive_resume_01
```

本报告保留待完成三对、诊断关闭对照、G4选型、独立物理线程、获选模式回归/30分钟长稳和最终配置交付；不是优化完成报告。
