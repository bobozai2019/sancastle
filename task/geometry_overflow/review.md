# geometry 海侧自动退水审阅

范围：用户要求的整体水位检测与右侧持续退水，仅在 test1_geometry 的 overflow v1 配置启用。默认机位右侧对应负 X 海边。不是竞品算法逆向。

## 所有权与物理语义

- Boundary 仍是声明输入；Water 是既有水阶段录制者，Pipeline 调度与完成态发布不变。新 boundary.glsl 由原 boundary dispatch 调用，无新线程、pump、权威资源、CPU 回读或静态节点创建。
- 原海侧潮汐公式保留；禁用扩展的固定输入与旧 shader 的水、动量和完整控制字节一致。旧 shader 留给历史引用，当前一阶与 MUSCL 共用新 shader。
- 采样仅每 0.5 实际模拟秒读取 128 点。活动期直接改水范围限于海侧边界与 x=1…23/z=68…187 窄带，其他区域由现有浅水传播。通过 1.04/0.98m 滞回避免临界切换；实际下降量受 dt、0.12m/s 与 0.90m 下限限制。
- 这是经授权的水汇物理变化，不是纯材质效果。实际增减累计原 control22/23；XZ 动量同比缩放。沙床与悬沙不在排水核中移除，沙量账本语义不变。障碍带不扣水。
- control104…127B 用作已配置的可选扩展，保持 128B 原生资源和原保存恢复通道。配置及来源 hash 标识新语义，未知旧配置不静默接纳。codec 对活动标志、有限值、实际时钟、检测次数及禁用时全零作检查。
- 首次检测若初态已过高且尚无边界记录，以检测均值初始化出口，避免从零水位直接跳变；正常 0.95m 初态不经过该分支。
- GPU timestamp 只在现有 profile_passes 启用时记录，默认关闭；它不读取水态或影响调度。

## 复验与证据

- tests/integration/geometry_overflow_probe.gd：正式场景 30 模拟秒，包含两次触发与一次停止、暂停、活动期精确恢复和非法扩展拒绝。原始报告保留在本目录 runtime.json，来源身份在 observations.sources。
- tests/integration/overflow_boundary_kernel_probe.gd：私有固定输入，检查旧边界一致性、湿位触发、局部化、逐格速率/下限、动量、水汇累计、低频采样、滞回与拒绝。
- tests/integration/geometry_overflow_cost_probe.gd：真实 1280×720 可见窗口、D3D12、GTX1050、VSync1、完整草木/水沙负载；边界 GPU 时间包含潮汐、检测、排水与同步，不是增量成本或整帧 FPS。二阶报告 cost.json，一阶报告 first_order.json。
- 默认初态约第 6s 检测均值 1.055m 时已触发，主要岸线 x≈0.81m；20s 均值约 0.965m 时已停止，30s 再次触发。初态、水槽、波传播和湿区定义影响岸线，不能对任意编辑地形保证固定岸线位置。
- 30s 运行与二阶成本先于“初始高位且出口为零”的防跳变分支；该分支不影响这些 0.95m 初态运行。最终核检查覆盖此分支，一阶运行使用最终 shader。每份报告保留其真实来源，不回写旧结果。
- kernel_v1 曾因测试把 f32 初始水深与十进制 double 1.1 相减，累计了所有未改格的表示误差而失败；改为实际旧水纹理逐格比较，未改运行核或放宽容差。原失败日志仍在可删除的 test_output/overflow/kernel_v1。

架构 seal 只更新上述已审阅的 boundary、codec、Water、MUSCL 录制、Pipeline 来源声明与 geometry 水位配置。未授权其他 writer 或动态工厂。当前技术说明已整合进场景说明、方案、规格、Word 与生成页面。
