# T05 GPU积时与物理帧等待定位

2026-10-11。完整目标保持，撤销/重做未执行。新增默认关闭CPU事务阶段记录：dispatch、receipt、publication、collision-ready、两次physics-frame回调。每事务常数次Time/Engine读数及碰撞替换成本，无GPU读回或模拟字段修改；实时探针记录accumulator/队列/shadow/prefetch状态。

142700实时E拖动：15准入/15终态，7.968Hz、p99 53.249ms/max605.811ms，全16/30Hz/p99均FAIL，末态沙/水发布PASS。最大停顿位于command9 physics_one10708925与physics_two11312155之间，间隔603.230ms；collision-ready10701610，CPU替换记录3.703ms。样本无tick_pending/shadow/prefetch，并且accumulator跨停顿保持0.008595238。这是C3时间定位，不是Jolt根因：当前配置Jolt，但没有native函数耗时证据；物理帧回调间仍可能包含渲染、driver或其他主线程工作。

代码直接观察：beach_gpu_entry._process在gpu_busy时立即return，beach_interaction_entry启动drain时也提前return，跳过原preview.playing期间accumulator+delta。修正这两个分支：仅playing=true时按同一个SIM_DELTA*4上限积时；不启动tick、不让命令与模拟并发、暂停不积时、不调整权威物理公式或30Hz tick长度。

142818复测：16尝试/16准入/16GPU终态/prefix，输入、终态、applied_log完整commands相同且ID各一次，status1，库存reservations与队列空；原负载及末沙/水发布PASS。46完成tick/3.003509s=15.3154Hz，p99 62.757ms、max64.771ms，30Hz/p99门仍FAIL。accumulator在GPU忙时递增并到原四tick上限，证实积时分支实际生效。Performance TIME_PROCESS/TIME_PHYSICS_PROCESS是引擎周期监视值，不把它当作特定帧精确native剖析。

本轮未出现旧600ms，不证明修复其根因；两个配置窗口不同tick/geometry，不把吞吐差值宣称精确因果收益。旧600ms证据保留，编辑期间积时缺失已修正，性能和真正首可见仍未解决。

scope：3秒筛查不代替300秒、交错A/B和长稳。旧队列回归结果保留，新连续用例更严范围仍FAIL；G4/76.2%不变。源版本、manifest/owner/log/原始字段与phase/sample/tick完成时间、hash索引都保存，相关目标进程终止。
