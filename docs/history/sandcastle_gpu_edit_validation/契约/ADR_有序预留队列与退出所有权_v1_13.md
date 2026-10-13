# ADR v1.13：有序预留队列与退出所有权

日期2026-10-11。落实v1已有64待排、串行、库存预留、代际及退出规则。数值公式、物理时钟和128byte布局不改。

GpuEditScheduler使用原ToolCommandQueue完成公共schema、ID高水位和(sim_tick,command_id)排序；待排上限64，另允许一笔在途。place按名义amount×strength预留，dig未回执不记资金；所有预留总和不超过settled+EPS，settled<0时拒绝新非零place。库存拒绝在同一无await调用中撤回暂入队项及ID高水位，不留下孤儿命令。policy/speed在入队时捕获。

执行从已校验队首消费，不再次submit，因此可以先执行较高ID的较早tick，随后执行较低ID的未来tick。wire available扣除其他未结算预留，并沿v1向下窄化float32；GPU真实回执决定账本。成功/拒绝/transport_failed/取消均有terminal记录，预留释放一次。旧单笔入口复用同一执行器并禁止与非空队列交叉执行。

停止接收后，reset取消待排、等在途完成、重建generation；close取消待排并先使旧generation失效。执行器的等待循环感知closed/generation改变，避免旧回调被丢弃后永久等待。关闭时render release等待receipt_pending消失，再释放editor buffer/RID；跨一个process_frame重试，不能在同一deferred周期自重排。

052052真实在途退出首次crash，GDScript栈定位_render_release→_retry_release：同一deferred循环不断重排，阻止帧/回执推进。修复跨帧等待后052129通过：close时实际receipt_pending=true，GPU回执约342ms后到达，随后才记录release；65条accepted（1在途+64待排）都cancelled，CPU库存2不变、预留0、旧回执忽略1次。实际GPU receipt仍记录其条件commit status1；这不当成CPU已结算或已发布。

资源/transport失败不是applied。053314明确注入“条件提交后、发起receipt readback前失败”，原GPU rollback恢复sand/h/sed/q双纹理及旧发布完成态；控制器隔离后拒绝新命令，3条accepted进入failed/cancelled，库存和revision不动、预留0。注入是故障测试，不声称触发了随机硬件故障。

本轮验证是实验后端调度API与正常可见窗口；实际UI队列绑定、collision staging回调所有权、保存边界/撤销/恢复仍属于后续T05整合。不因本ADR放行G4或替换正式入口。
