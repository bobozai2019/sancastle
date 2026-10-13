# ADR v1.57：自有进程原生快照与捕获窗口修正

2026-10-11。WCT不能暴露等待对象，增加单次normal+threadinfo minidump诊断。自有sampler调用本机DbgHelp.MiniDumpWriteDump，PROCESS_QUERY_INFORMATION|VM_READ，仅自有目标PID；不取full memory，不操作用户编辑器、其他进程或竞品。只在实时probe心跳超过200ms且测量窗口active时触发一次。dump有扰动，不用于正式成本验收。微软API参数及权限按官方说明核对，DLL/工具/source/owner留存。

144539首版成功保存144038字节dump、解析31线程AMD64上下文和模块。但触发UTC1791701228068837比测量结束UTC1791701227725590晚343247us；原因是窗口结束后心跳没有关闭。该快照明确标为window-out invalid，不用于长帧或NVIDIA/Godot函数归因。保存了旧probe/sampler版本。解析器仅报告RIP/RSP、模块RVA、原始栈映射地址候选和nearest exports，不做unwind、不把地址候选称调用链，过远导出名不是private函数符号。

修正：测量结束立即将心跳begin写0后再drain；sampler要求begin>0才触发。144848负对照完成：心跳begin=0、无dump/无dump_events，采样末UTC覆盖测量结束及drain，证明无停顿时不会把收尾作为长帧。该窗口max62.584ms未触发200ms门，不证明已捕获/解决真实600ms根因。

144539与144848各16输入/16终态、原负载/末沙水发布PASS；前者15.2693Hz/p99 48.984ms、后者15.5884Hz/p99 61.179ms，性能门仍FAIL。两次都有加载等待，沿同一PID终态、未因runner观察超时重启。目标及sampler退出。旧677/723ms证据仍保留，下一诊断需要active窗口内真实停顿快照及可靠native unwind；本机只有DbgHelp组件、无cdb工具，符号/栈覆盖限制明确保留。

普通默认不开启NativeStack/SampleCpu，runner manifest现在包含sampler源码；实际snapshot源与hash记录。G4/76.2%不变，撤销/重做未执行。
