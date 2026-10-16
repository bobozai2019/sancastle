# G2 纯数据worker

日期：2026-10-14。Gate：[已完成]。仅纯数据实现与任务回收通过，正式碰撞接线、Jolt与生命周期发布还未验收。

交付：`scripts/collision/collision_prepare_job.gd`、`collision_prepare_scheduler.gd`、`tests/integration/collision_worker_probe.gd`。新增脚本没有全局class_name，不重复注册类；默认场景未引用这些候选。共享collision仅保留T00已验收的默认关闭计时，没有提前改变提交策略。

## 实现边界

独立raw/chunks快照、固定Slot容器、每slot唯一worker写者，解码后只读高度做有限值检查，完整float32结果不量化。主线程完成检查后wait回收一次，再汇总全批status；非法slot不返回可发布子集。没有Node/Shape/RD/solver/账本访问；实际thread_id独立核对12组，worker全部在非主线程执行，serial全部在主线程。

单活动+四等待，2MiB预算；16块单请求保守raw/输出净payload139392字节，五请求预留696960字节。背压不占ID；关闭取消等待但保留活动ID到poll回收，不假装强杀worker。T03必须接入正常异步drain与Node突然退出的独立回收者；本Gate不宣称已解决Node退出。

## 新验证

实际引擎4.7.2、精确源/命令在 `test_output/physics_threading/t02_worker_repeat/manifest.json`。headless纯数据probe **583/583通过**，Godot exit0、无SCRIPT ERROR/ERROR/WARNING。

- 1/4/16块，serial/worker1/2/4，随机正负/陡变有限高度与负零；独立oracle直接比较原始slot字节，逐位一致，不调用准备函数作oracle。
- 首/中/末位置NaN、正Inf、负Inf：全批non_finite、结果chunks为空；错误长度、重复/越界块、float身份、巨大域整数溢出前置拒绝。
- 2^53以上int64身份保留；准入后调用者改raw/chunks/generation不影响已捕获快照。
- 5批容量、背压不占ID、重复ID拒绝、关闭后拒绝准入、四等待取消、活动任务正确回收；重复poll不重复返回/回收。
- 300批16块连续准备全部逐位验证，300个group全部回收，最终payload=0；静态内存监视前后差-4556字节。该值不是RSS或长稳证据。
- 300份交错纯数据成本样本（每块数×策略25次）均验证数据完整、回收与payload归零。另有最初283项运行记录，原日志和UTF-8读取修正保留，不复写旧结果。

## 数据开销（p95 μs）

| 块数 | 策略 | 主线程准入+轮询CPU | 整笔准备墙钟 |
|---:|---|---:|---:|
| 1 | serial / worker1 / worker2 / worker4 | 99 / 95 / 139 / 110 | 117 / 6906 / 6919 / 6920 |
| 4 | serial / worker1 / worker2 / worker4 | 338 / 159 / 213 / 195 | 365 / 6895 / 6953 / 6987 |
| 16 | serial / worker1 / worker2 / worker4 | 2961 / 800 / 730 / 606 | 3228 / 7889 / 7364 / 6904 |

来源 `cost_summary.json`和原cost_samples。CPU是每次enqueue/poll调用墙钟求和，可能受抢占；整笔墙钟包括下一process_frame收集等待。4任务请求实际只观察到2个worker线程，符合本机低优先级上限，不把请求数当并发实数。小批成本可能退化；这不是1080p真实游戏性能，不能据此采用默认worker或冻结T04阈值。

下一步G3：默认关闭候选接入读回/影子路径、主线程版本重查与shape提交、正常关闭/恢复/切换和突然Node退出回收，再做真Jolt与相关原工具链回归。G4才决定实际任务数/小批阈值和是否保留候选。
