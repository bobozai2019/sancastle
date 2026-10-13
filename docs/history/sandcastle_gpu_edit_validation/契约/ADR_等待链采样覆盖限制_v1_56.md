# ADR v1.56：等待链与线程名称采样的覆盖限制

2026-10-11。承接v1.55，只扩展自有PID诊断，不改GPU/物理/时钟。采样器按本机Windows SDK10.0.26100.0的wct.h绑定280字节WAITCHAIN_NODE_INFO及16节点上限，同步WCT Flags=0不追踪其他进程。读取线程GetThreadDescription与创建时间，优先最早创建线程及名称含render者，每100ms目标间隔记录WCT；没有提权、注入、线程暂停或内存dump。sampler_error.log和完整源版本/hash保留。

143938目标PID2468、采样PID10892。加载阶段较慢，测量起点Godot相对clock88.696608秒，沿同一PID继续到终态，未因runner60秒观察timeout重启。16输入/16终态、原80浪负载与最终沙水发布PASS；33tick/3.010768s=10.9607Hz，p99 58.074ms/max63.517ms，性能仍FAIL。未复现旧600ms区间，不能称其修复。

38线程名称全部为空，无法靠名称可靠选render线程。因此实际仅采最早创建线程20376。755次WCT调用全部返回成功；窗口内25次，15次singleton Thread/Blocked、10次singleton Thread/Running，无锁对象、持有线程、多个node或cycle。原wait_ms字段未作秒数/等待区间推导。此为C3观察，不能把singleton running当CPU忙、不能由成功返回声称找到了完整等待链。

[微软GetThreadWaitChain说明](https://learn.microsoft.com/en-us/windows/win32/api/wct/nf-wct-getthreadwaitchain)指出，不被支持的同步对象也可能只返回单个节点；等待链本身随时间变化。本轮确认WCT可调用，但当前诊断没有捕获具体primitive/owner。不是权限拒绝、也不证明没有锁或GPU等待。线程名称缺失作为unknown保留。

结论：WCT/名称路径不能给当前长帧定因，不继续机械重复同一采样以等PASS。保留v1.55的677ms/15.625ms CPU等待反证，下一步需要native调用栈或更细同步剖析；普通恢复、实际首可见、T06和长稳仍未完成。目标及采样器已终止，G4/76.2%不变，撤销/重做未执行。
