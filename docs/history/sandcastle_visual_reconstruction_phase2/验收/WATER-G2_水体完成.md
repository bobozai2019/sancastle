# WATER-G2 水体独立验收：通过

日期：2026-10-06。范围仅 T09 水体，T10 沙模型尚未启动。W01–W05 分步证据见各报告。

## 动态岸线复测

固定 `water_v1`、2× 显示网格、物理 256²、`test_packet` tick 8 振幅 0.18 m/时长 6 s。W03 原 0.006 m 水面显示偏移在 tick 480 掠射镜头产生内部干地误盖 4/188（2.13%，未过 <2% 门）。试验 0.003 m 后，静态和动态 tick 300/360/480 的俯视最大干地外扩为 0.289/0.289/0.289/0.333 格，最大湿域内缩为 0.489/0.489/0.444/0.467 格，均 ≤0.5 格；三个镜头湿域内部漏盖均为 0。干地内部误盖率最大值依次为 0.36%、1.00%、0%、1.58%，均 <2%。因此夹具水面偏移正式改为 0.003 m，不调整 W03 的物理采样或门槛。

实际命令：

```powershell
pwsh -NoProfile -File tests/visual_phase2/run_water_dynamic_shore.ps1 -Tick 300 -WaterBias 0.003
pwsh -NoProfile -File tests/visual_phase2/run_water_dynamic_shore.ps1 -Tick 360 -WaterBias 0.003
pwsh -NoProfile -File tests/visual_phase2/run_water_dynamic_shore.ps1 -Tick 480 -WaterBias 0.003
```

以上均输出 PASS；量化证据为 `W03_mask_2_bias3_water_manifest.json` 与 `W06_wave_mask_{300,360,480}_bias3_water_manifest.json`，各含三镜头遮罩和俯视图。原 0.006 m 的 tick 480 探针结果仍在 `W06_wave_mask_480_water_manifest.json`，作为失败对照。

## 已确认的 W06 项

- [x] 最终 0.003 m 偏移重录的 [W06_water_sequence.avi](W06_water_sequence.avi)：40 秒、1202 帧、30 FPS，斜俯、近景、掠射镜头切换，浪前/绕流/退浪时序。静水段约 2 秒，W05 独立无波 10 秒探针见 W05 报告。命令 `pwsh -NoProfile -File tests/visual_phase2/run_water_foam_movie.ps1 -ArtifactName W06_water_sequence.avi`，输出 PASS。
- [x] 动态岸线三个时点通过 W03 原门。
- [x] tick 20 检查点重启，继续至 tick 1820（60 s）；水深、x/z 动量、沙、岩、白沫历史逐字节一致，源汇账本一致。命令 `pwsh -NoProfile -File tests/visual_phase2/run_wave_checkpoint.ps1 -TargetTick 1820`，输出 PASS。
- [x] 原数值、湿干、透明与新增波包/白沫回归通过。`tests/run.ps1` 的 17 个模拟契约、3 个预置场景及拓扑探针，`tests/run_scene_hash.ps1` 的六个固定输入哈希已过；本轮 `pwsh -NoProfile -File tests/visual_phase2/run_water_w06_regression.ps1` 12 项均过：低角透明未盖湿域 0.04425%、干沙误盖 0.00177%；GPU 潮汐升降与 CPU 单步误差 ≤3×10⁻⁸ m、CFL/30 tick 湿干与水账本；跨 tick 重放、GPU 检查点；W04 波包/长程到达；60 秒水/动量/沙/岩/白沫检查点续跑；W05 无波和有波白沫。
- [x] 可见全屏 1080p、VSync 关闭，预热 30 秒后连续 300.012 秒采样：58,027 帧，墙钟 p50/p95/p99 为 5.136/5.693/6.056 ms（最大 15.705 ms），模拟 30.002 tick/s，均过目标；GPU 为 NVIDIA GeForce GTX 1050。原始 [CSV](W06_1080p_frames.csv) 与 [汇总](W06_1080p_summary.json)。期间 CFL 最大 3 子步，无过载/NaN/负水，沙岩哈希固定。命令 `pwsh -NoProfile -File tests/visual_phase2/run_water_acceptance.ps1 -Mode frame -Seconds 300 -Warmup 30`，输出 PASS。
- [x] 新水夹具可见 1280×720、VSync 关闭、预热 30 秒后连续 1800.009 秒：61 个趋势样本，模拟 30.0004 tick/s，每个 30 秒区间均为 30.0 tick/s；无 NaN、负水、过载，沙岩哈希不变。静态内存首尾 95,904,111/95,904,735 B，范围 4,252 B；显存读数全程 72,986,624 B。原始 [CSV](W06_water_soak.csv)、[汇总](W06_water_soak_summary.json)、[独立分析](W06_water_soak_analysis.json)。命令 `pwsh -NoProfile -File tests/visual_phase2/run_water_acceptance.ps1 -Mode soak -Seconds 1800 -Warmup 30` 与 `python tests/visual_phase2/analyze_water_soak.py` 均通过。抽样水量减源加汇范围 0.503 m³，审计和账本采样可能隔一个 revision，此值只作趋势，精确闭合由 W04 同 revision 波包探针验证（5.98×10⁻⁹ 比例）。
- [x] 水五项逐项评分 **9/10**；[water_profile_v1.json](water_profile_v1.json) 冻结 256²/0.125 m/30 Hz、2× 显示网格、0.003 m 水面偏移、光学/波包/白沫参数与 11 个源码 SHA256。床面读取 `SandcastleBedDisplaySampler.sample_bed/sample_world`、WaveRequest 与 foam_history 检查点规则沿 W03–W05 契约冻结。命令 `python tests/visual_phase2/freeze_water_profile.py` 输出 PASS。

## 水五项最终评分

| 项目 | 分数 | 依据与边界 |
|---|---:|---|
| 浅水透底 | 2/2 | W02 三镜头可见 0.02/0.08 m 水下脊沟，0.25 m 深水遮蔽增强；光学开关不动水状态。 |
| 青绿深浅 | 2/2 | W02 三镜头浅青绿至深青绿层次、视角反射与高光分项对照。 |
| 连续岸线 | 2/2 | W03 静态及本报告动态 300/360/480 tick 均通过 ≤0.5 格偏移、<2% 内部误盖/漏盖门。 |
| 推进浪前 | 2/2 | W04 水深/动量到达曲线与三镜头 W05 图片，浪前绕固定高地两侧传播。 |
| 白沫时序/亮纹 | 1/2 | W05 无波、入浪、局部衰减及录像有完整时序；近景亮纹仍呈较规则网状，故按“有显眼伪影”保守计 1 分。 |

总分 **9/10**，透底、岸线、浪前均满分。以上是主执行者按契约量表、最终 0.003 m 配置截图与录像的自评；近景亮纹规则网状伪影保留为已知限制。

WATER-G2 通过；T09 水体任务独立完成。T10 可从冻结 profile 开始 S01。
