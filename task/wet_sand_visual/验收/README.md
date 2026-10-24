# 验收证据约定

当前无本方案实施结果。方案文档检查不计作运行/视觉/性能验收。

每个 Gate 完成后保存一份简短报告：范围、逐项结果、实际命令、源码/资源/profile hash、证据链接、失败与限制。失败报告保持原样，重试另建目录；不回填成旧 PASS。

建议布局（执行时创建）：

```text
验收/
  g0_baseline/     source_manifest.json、configuration、基线 raw/关键帧
  g1_visual/       输入、M 与接触序列、同状态图、ROI、连续片段
  g2_lifecycle/    存档、迁移来源、恢复/物理对照、负例
  g3_cost/         硬件与实际配置、原始采样、分析、稳定性记录
  G0.md ... G3.md  结果与证据索引
```

Godot/机器输出和脚本路径使用完整英文路径。可以先输出到 `D:/godot/project/sandcastle/test_output/wet_sand_visual/`，但交付前把必要唯一证据封存到上述英文子目录；正式资源不得依赖临时输出。

每组视觉比较记录实际 seed、完成 tick、generation/state_seq/revision、实际推进时间、相机、曝光、后端、分辨率、配置与消费资源 hash。不同场景不做整图相似度结论。单变量截图对照和连续时间观察分别建索引。

成本报告区分新增纹理原始字节估算、实际显存、冻结帧着色成本与实时更新总成本；不可用 tick/frame 编号差冒充秒数。无真实可见窗口或实际负载不一致时，不能将结果标为代表性性能通过。
