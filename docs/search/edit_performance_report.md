# 堆挖沙卡顿与竞品 GPU 编辑调查

日期：2026-10-10。范围：现有成本证据、Ground/Readback ComputeShader、10 份 RDC 的有效绑定与沙面绘制数据。没有分析竞品业务方法，没有改正式模拟、场景或 profile，没有新增性能运行。原始包和 RDC 前后 hash 一致。

**结论：找到了可以借鉴的 GPU 笔刷计算方式；当前项目的主要编辑开销来自 GPU→CPU 的等待及沙影子校验。原作笔刷调用调度、CPU 同步策略和动作实际耗时仍未知，不能宣称已恢复完整性能方案。**

## 当前项目：历史瓶颈与最新入口

当前基本链路仍是：等待同 revision 的 GPU 沙图 → CPU 解码/校验 → CPU 应用库存守恒的笔刷 → 上传绝对高度 patch → GPU 绘制。`_start_tick()` 在需要沙影子同步时等待；编辑与该 tick 的继续共同依赖读回完成。GPU `shallow_tool_patch.glsl` 提交的是 CPU 已经算好的绝对沙高/压实值，没有在 GPU 求笔刷分布与实际移沙量。

| 观测 | 数据 | 解释与边界 |
|---|---|---|
| 优化后的 CPU 笔刷 | 约 0.148–1.155 ms | 全域枚举已改为包围盒；不是当前几十毫秒停顿的主要分段。274 项等价检查属于已有证据。 |
| 历史热编辑读回等待 | 19.735–29.102 ms，中位 22.468 ms | `render_request_exit→readback_callback`，同一时钟；包括队列/回调延迟，不能全当作数据传输时间。 |
| 历史主线程解码/校验及发布阶段 | 38.298–40.409 ms，中位 38.929 ms | `validate_enter→resume_enter`，会形成主线程长间隔；该数字不是最新正式入口每一笔的开销。 |
| 工作线程诊断候选 | 请求→恢复中位 67.501→37.363 ms | 不可变读回数据后台解码校验，主线程发布；跨运行环境不完全相同，整窗收益不能严格归因。 |
| 最新正式入口 20 笔反馈 | 最大 60.818 ms，20 笔全部完成 | 单次提交到首绘制帧符合 100 ms，不能抹去历史冷首笔 200.763 ms 失败。 |
| 回收版同逻辑 60 秒完整编辑负载 | 帧 wall p99 36.937 ms，29.959 completed tick/s | GTX 1050、可见 1920×1080、D3D12、VSync off、10 秒预热、持续浪；仍未过 RG4。此成本运行发生于正式入口整合前。 |

最新正式入口 `scripts/visual/test1_beach_edit_worker_entry.gd` 已把显式沙同步回调 `_on_shadow_field()` 的解码/全图校验移入 `WorkerThreadPool`，主线程继续核对 generation/revision 后发布。源码 SHA256 `c9b4a4d15b9fe1df97f653df9330a08ccf54312fa275f9d505873f850f9c0582`；正式场景 SHA256 `8633ae81fd3b95678d296cac09c3b22268a0af65ea137a845da642c7e4b0bcd5`。G04 整合复验已有库存闭合、64 个碰撞 chunk 与恢复 hash 一致证据。

**尚存另一条路径：**继承的 `_record_sand_prefetch()` 仍在主线程把 256² float32 沙图解码并逐格校验。最新 20 笔中大量命中预取；不能把“显式同步回调已移到工作线程”等同于“所有沙读回均已移到工作线程”。它对最新实测停顿的占比要再用同一时钟追踪，当前仅确定代码路径存在。历史小范围 4 KiB 读回替代 256 KiB 整图的配对中位几乎相同（45.551/45.552 ms），也没有证据支持继续仅靠缩小 payload 消除等待。

完整成本还有非编辑长尾：回收版 60 秒运行中，按完成 tick 为提交 tick 或其后一 tick 的定义，编辑附近 142 帧只有 1 帧超过 33.3 ms；远离编辑的 3768 帧有 93 帧超过。它支持编辑局部尖峰已减少；邻域窗口不覆盖任意延迟的全部后果，也不能直接证明剩余长尾由某个引擎/GPU 内部步骤导致。

代码定位：共享预览 `reference_preview.gd:1246/1277/1312/1721/2532`；正式工作线程入口 `:8/19/32`；`tool_command_queue.gd:64`。所有引用文件及原始 CSV 的 hash 见 [机器汇总](../../task/sandcastle_test1_reverse_rebuild/evidence/edit_performance_inquiry_20261010/analysis_summary.json)。

## 竞品直接证据

### GPU 笔刷能力：C3；实际动作调用与性能：C0

源 `sharedassets0.assets` SHA256 `6dd7bb6bc7d926fd43c08d22c9c767b7edf531cf11a4a555fcd41830f2f9c721`，ComputeShader 对象 `:640 Ground`。其 `Paint` DXBC 为 8916 字节，线程组 32×32×1，renderer 2/18 两个包内变体已导出原始对象、typetree、字节码和反汇编。

`asset_640_renderer_2_Paint_0.asm.txt` 的具体证据：

- 第 18–26 行：常量、笔刷纹理 t0、32 字节 stride 的 `brushData` t1、16 字节 stride 的沙床 UAV u0；线程按沙床二维坐标定位格子。
- 第 34–158 行：空间变换、形状/遮罩及衰减计算；第 162 行直接读取当前 u0 格子，第 175–177 行只读取 t1 **第 0 条记录**的偏移 8、20、28。不能据 stride 或资源名宣称它是多笔命令批处理队列。
- 第 178–217、260–280 行：加减、混合、模式选择及高度上下限处理；第 288–312 行重新编码并写回 u0。GPU 可以根据笔刷参数直接改沙床高度及相关状态，而不是必须上传 CPU 算好的逐格绝对高度。
- 第 218–259 行存在邻格读取分支。枚举对应何种用户工具、各分支实际使用、精确体积/库存结算均未确认，不能把该核原样替换本项目守恒笔刷。

十份 RDC 的所有 compute dispatch 已按包内 DXBC SHA256 查找，**没有匹配到 Ground.Paint 调用**。因此只有“原包存在功能非空的 GPU 笔刷实现”是直接事实，不能证明这些帧记录了编辑动作，不能推导其冷首笔/连续堆挖耗时。shader 字节码不是原始 HLSL。

### GPU 沙床直接用于绘制：C3，限捕帧

test1 的 `Ground.HeightIntegration` E1478 写入 `ResourceId::139571`（8 MiB）。该资源使用表同时包含 E5006 等 VS 读取；既有 E5006 vertex disassembly 第 13–25 行读取 stride16 沙床并解码高度用于顶点变换。它把 GPU 沙床结果直接送入顶点着色，构成已捕获的模拟→绘制通路。

这支持本项目继续使用权威 GPU 高度驱动可见沙面。它不证明竞品 CPU 完全不持有沙影子、碰撞无需更新，或所有编辑都避免 CPU 同步；不能把绘制通路证据扩大为整个引擎的无读回结论。

### Readback 是规则降采样，不是已证实的小型账本：C3/C0

ComputeShader `:646 Readback.Update` 的包内字节码与每份 RDC 运行时 shader 精确匹配；读取 stride16 的 ground/water cells，写 stride32 的采样记录，指令包括邻格插值。

| 捕帧 | 有效事件 | ground 尺寸/容量 | water 尺寸 | 采样输出尺寸/容量 |
|---|---:|---|---|---|
| test1 | E1640 | 1024×512 / 8 MiB | 512×256 | 256×128 / 1 MiB |
| test2 | E1368 | 1024×1024 / 16 MiB | 512×512 | 256×256 / 2 MiB |
| 其余 8 份 | 见机器汇总 | 1024×512 / 8 MiB | 512×256 | 256×128 / 1 MiB |

有效常量 cb139 与 cb141、输出 buffer 的完整字节快照和 dispatch groups 相互吻合。输出相对于全 ground buffer 小 8 倍，仍比本项目 256 KiB 沙图大。输出并非已确认的几十字节结果、脏区列表或 GPU 库存归约。`Readback.Paint` 的 116 字节变体无有效操作，不能当作功能实现。

这些帧中输出 resource 的已记录使用只有 barrier 与计算写入，没有相关 copy action；**CPU 是否映射、读回频率、跨帧缓存、是否等待或另帧消费仍未知**。API 使用表不足以证明 CPU 从不读它。本次未查 CPU 业务调用链。

## Godot 适配建议：尚未实现

可借鉴的重点是 **GPU 根据笔刷参数修改现有沙床，并把它直接交给沙面渲染**。本项目目前虽然模拟和 patch 提交在 GPU，决定这笔沙高的工作仍依赖整图 CPU 影子，故会在操作时等待最新数据。

1. **先补齐现有校验路径。**显式同步和预取都用不可变字节在后台解码校验；主线程只发布匹配 generation/revision 的完成态与结算。针对预取命中、未命中、冷首笔、暂停编辑、退出及恢复分别追踪，不删除校验或允许旧 revision 的绝对 patch 覆盖侵蚀后的沙床。这是当前项目适配，竞品线程调度未知。
2. **验证 GPU 原生守恒笔刷。**上传位置、半径、形状、请求体积、可用库存、command_id/generation 等参数；在 GPU 计算局部权重及可移沙量，归约/归一化后写入当前权威沙场，并位于明确的 tick 编辑阶段。可见绘制和随后的水沙求解消费同一完成态，避免等整图沙影子回来才开始编辑。局部包围盒 dispatch、体积归约和库存结果缓冲均为待验证适配，不是本次已找到的原作实现。
3. **按用途回传结果。**候选是异步小型完成记录（实际移沙量、异常标志、脏 chunk、命令与版本身份）；碰撞及 CPU 命中需求再更新相应高度区域，保存/恢复另在一致的 tick 边界取完整状态。账本以确认的实际量结算，库存需预留防止连续命令超支；失败、取消、世代变更必须明确回滚/释放。不能只让画面先变而让库存、碰撞与后续编辑失去一致性。

GPU 原生方案会改变笔刷执行位置，必须先记录 ADR/契约影响，验证现有请求体积、非负、沙量加库存闭合、顺序、恢复与碰撞反馈。不能直接复制竞品的量化格式、未解码模式或假定其库存规则等同本项目。前一份大块入水排水调查属于另一项物理语义，GPU 笔刷改造本身不会自动修复水被抬高的问题。

Godot 官方文档说明 `texture_get_data()` 会等待 GPU，异步读取则经后续帧回调交付，延迟关联 `frame_queue_size`。异步 API 消除了调用处的直接阻塞，并不消除业务链路对返回数据的等待；现有时钟追踪另量出了回调后的 CPU 阶段。[RenderingDevice 文档](https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html#class-renderingdevice-method-texture-get-data-async)

## 复验、反证与交付边界

- 原包导出：`tools/.venv/Scripts/python.exe tools/investigate_edit_kernels.py`；UnityPy 1.25.4、Windows D3DDisassemble，DLL/script hash 均在 kernel_manifest。已完成目录有保护，复验应输出新 run 目录。
- RDC：`D:/other_software/RenderDoc/qrenderdoc.exe --python D:/godot/project/sandcastle/task/sandcastle_test1_reverse_rebuild/tools/investigate_edit_rdc.py`；RenderDoc 1.46，runtime_retry_1 的每个源、事件、ResourceId、字节偏移/长度和 hash 可追溯。最初字段名错误导致的部分导出及失败 manifest 单独保留，没有改写为成功。
- 汇总：`python -X utf8 tools/analyze_edit_performance_inquiry.py`；引用既有原始 CSV/manifest 与当前源码，不重新产生性能 PASS。
- 要确认竞品的完整方案，缺的是 **实际堆挖动作前、中、后的带时间戳 GPU 捕获及动作耗时**；目前十帧均无 Paint 精确匹配。无需以此扩展到竞品业务反编译。
- 要确认当前剩余卡顿，下一项有区分力的观测是正式入口同一笔的预取/显式同步、后台校验、主线程发布、碰撞更新与首绘制共用时钟；再做单变量候选对照及短运行负例。稳定后才做完整成本验收。

本次不修改旧失败、验收门槛或 14/15 进度。索引及本专项产物校验见 [provenance_validation.json](../../task/sandcastle_test1_reverse_rebuild/evidence/edit_performance_inquiry_20261010/provenance_validation.json)；具体快照和匹配见 [analysis_summary.json](../../task/sandcastle_test1_reverse_rebuild/evidence/edit_performance_inquiry_20261010/analysis_summary.json)、[kernel_manifest.json](../../task/sandcastle_test1_reverse_rebuild/evidence/edit_performance_inquiry_20261010/kernel_manifest.json) 与 runtime_retry_1/runtime_manifest.json。
