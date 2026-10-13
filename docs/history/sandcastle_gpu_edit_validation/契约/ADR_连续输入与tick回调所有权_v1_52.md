# ADR v1.52：连续输入与tick完成回调的GPU所有权

2026-10-11。新增3秒完整负载实时E拖动筛查，16个真实引擎鼠标事件按200ms时间计划发送，窗口内playing=true、不显式调用_ticks、不增加物理字段逐帧读回。实际帧间隔和tick_finished内部完成时间戳记录；短窗口不替代正式300秒或长稳验收。

142229修正前：16获准入、11 GPU终态，缺ID2/4/7/10/16恰好均在tick中提交。原reference_preview._tick_finished及shadow回调调用_dispatch_paused_patch，后者使用CPU _apply_due_tool_commands并上传patch，绕过GPU scheduler reservations/policy/terminal；此源码事实加缺失模式为C2归因，缺失运行未导出CPU applied_log，不能冒称已逐笔观察其CPU消费。

beach_interaction_entry覆写该继承hook：若队首ID由GPU scheduler reservation所有，保留队列，必要时启动同一_drain_input；当前tick完成和shadow回调不能再把该命令交给CPU。非scheduler所有的原CPU命令仍调用super，保留smooth/compact普通路径接口；该接口兼容不是本轮完整CPU混合恢复验证。

142342修正后：16尝试、14获准入、14GPU终态/应用日志，完整command序列逐位结构相同，ID各一次、status1。无已准入静默丢失。两次尝试未入队，记录一次collision_pending，另一次未产生eligible intent；all16要求仍FAIL。输入串联发生一次604.268ms帧停顿，计划时间已过的三次事件在随后同帧发送形成真实积压（max_pending3），不可当作稳定5Hz准时输入。

完成吞吐54ticks/3.01875s=17.8882Hz（修正前），修正后29ticks/3.002308s=9.65924Hz；后者p99 frame49.005ms/max604.268ms，30Hz及p99门FAIL。长帧根因未查明，不凭单次称可重复编辑关联。两轮均原80浪/侵蚀负载继续、最后sand/water发布逐位PASS。未隐藏失败或放宽需求。

142439现有全场景队列7项PASS：64pending/2拒绝、真实GPU在途新增、65终态/策略/库存预留、authority/发布/碰撞、背景不编辑、库存预留取消、原负载继续。撤销/重做未执行。

新探针和旧失败代码版本、owner/manifest/log/原始状态/timing/json/hash全部保存，进程终止。G4/76.2%保持。后续需定位长帧、tick等待及GPU工作期间积时/调度语义，再验证持续输入与30Hz；本ADR仅修复已准入GPU命令被CPU回调抢走的问题。
