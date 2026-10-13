# ADR v1.55：长物理帧区间的自有进程CPU采样

2026-10-11。不改实际模拟、碰撞或GPU策略。Windows WPR CPU.Verbose.File采样启动被OS权限策略拒绝0xc5585011，start.log与owner.started=false保留，未将无trace当PASS、未申请提权或操作其他录制。改用仅自有Godot PID的GetProcessTimes/GetThreadTimes：10ms目标周期，250ms发现线程；进程退出后关闭句柄并写JSON。不采集其他进程、内存内容或线程栈。UTC-start把Godot相对clock与采样UTC对齐，窗口完结仍取既有completed tick时间戳。

143620目标PID16948、采样PID5468：1011份样本、末样本35线程，均已结束。持续E拖动16输入/16终态、原负载及末沙水发布PASS，47完成tick/3.583945s=13.114Hz、p99 53.801ms/max677.036ms；性能门仍FAIL。UTC-stop字段在drain后填入，仅用于结束诊断，不能拿它替代测量stop_us；long_frame_cpu_alignment只使用UTC-start偏移。

最大帧gap677.036ms，对齐采样实际间隔677.406ms，整个Godot进程CPU仅增加15.625ms；仅线程18664增加15.625ms，其余该区间已发现线程零增量。第二53.801ms gap对应31.25ms CPU，显示采样可以观测忙区间。原样本/hash、对应线程与对齐误差逐行保存。

结论C2：长区间大部分是等待/未获调度，反证“Godot进程在此期间连续CPU计算近600ms”。不能据此说已证实GPU或物理锁；可能是render/driver、kernel等待、OS调度或其他阻塞。尚无native栈/等待对象证据，CPU统计约15.625ms量化，采样有开销、UTC跳变未独立校验；不把此运行当正式性能测量。

新增-sampleCpu只启动拥有明确targetPID的后台采样器，owner和源码hash留存；普通运行默认不开启。新探针时间字段/采样raw/index保留。后续应取线程名称及等待链/同步对象以区分阻塞原因，避免继续以重建形状/调参数替代定位。G4/76.2%保持，撤销/重做未执行。
