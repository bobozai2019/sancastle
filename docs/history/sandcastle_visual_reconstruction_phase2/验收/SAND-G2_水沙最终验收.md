# SAND-G2 水沙最终验收：通过，保留一项历史未定位问题

日期：2026-10-06。T09 WATER-G2 与 T10 SAND-G0/G1、S05 均已通过，本报告验收最终耦合档。正式物理域 256²、0.125 m/格、30 Hz，CFL Courant 0.35；耦合夹具显示 2× 沙面与水面重建，启用 T09 透底、岸线、白沫，启用侵蚀、沉积、湿度/压实和有界屈服。最终配置见 [sand_profile_v1.json](sand_profile_v1.json)，历史独立水配置见 [water_profile_v1.json](water_profile_v1.json)。水配置中的源码 SHA 是 W06 冻结时的历史快照，沙阶段扩展了共同入口；当前沙配置单独保存 13 个现行源码 SHA。

## 回归、守恒与独立重启

- 基础 `tests/run.ps1`：17 项模拟契约、3 项预置场景、拓扑探针通过；`tests/run_scene_hash.ps1` 六个固定输入哈希通过。
- 最终 `tests/visual_phase2/run_water_w06_regression.ps1` 12 项全部通过，覆盖透底、潮汐、CFL、跨 tick 重放、波包到达、60 秒水/动量/沙/岩/白沫重启和白沫时序。
- 13 项定向回归通过：沙材料 3 工况、侵蚀守恒/参数、水下挖填、NUM-09 热点、结构预览/保存、原工具/撤销、存档版本、`sand_v1` 工具与支撑塌落 A/B。最终修改后又复跑 W06 12 项、旧存档版本、S02 支撑及工具，均通过。
- [S05 波/无波分析](S05_coupled_analysis.json)：无波到 tick 900 无失稳；有波 tick 240 触发海侧 102 格局部支撑失效，塔原占地沙量到 tick 300 减 0.936 m³。四个同完成态 GPU 样本床沙+悬沙最大相对闭合误差 7.76×10⁻⁸，水源汇闭合最大相对误差 1.53×10⁻⁷；无负格。采样碰撞最大高度误差 0.000261 m，回读+替换最大 59.48 ms，小于 100 ms 门。
- [S06 耦合存档](S06_coupled_checkpoint.json)：tick 900 保存，独立实例重启并续跑 60 秒到 tick 2700。沙、悬沙、湿度、压实度、水深、x/z 动量和白沫历史共八类 GPU 状态逐字节一致；自动支撑事件版本 2 的 generation、sensor revision、应用 revision 和趾部沙量恢复正确。旧版本门与原 `sand_v1` 事件版本 1 仍通过。

## 正式性能与四场长稳

[耦合档 1080p CSV](S06_coupled_frame.csv) / [汇总](S06_coupled_frame_summary.json)：可见全屏 1920×1080、VSync 关闭、预热 30 秒后连续 300.032 秒，26,440 帧；整帧 p50/p95/p99 为 13.367/17.186/23.136 ms，模拟 30.0002 tick/s，分别满足 p99≤33.3 ms 与 ≥30 tick/s。CFL 最大 3 子步，无过载、NaN 或负格；GPU 为 NVIDIA GeForce GTX 1050。没有用隐藏窗口、降物理域或降低分辨率替代此门。

四场均为可见 1280×720、VSync 关闭、预热 30 秒后按墙钟实跑至少 1,800 秒，每 30 秒留一行，61 行/场。[独立分析](S06_final_stability_analysis.json)通过：

| 场景 | 墙钟秒 | tick/s | 最大沙账本误差 m³ | 30 秒样本静态内存范围 | 显存首尾差 | 异常格 |
|---|---:|---:|---:|---:|---:|---:|
| SCN-01 `preset0` | 1800.001 | 29.99998 | 0.007892 | 7,712 B | 0 B | 0 |
| SCN-02 `preset1` | 1800.018 | 29.99970 | 0.006866 | 7,880 B | 0 B | 0 |
| SCN-03 `preset2` | 1800.006 | 29.99989 | 0.001693 | 7,700 B | 0 B | 0 |
| 新耦合 `sand_coupled_v1` | 1800.012 | 29.99980 | 0.000258 | 24,564 B | 0 B | 0 |

原始文件：`S06_{preset0,preset1,preset2,coupled}_soak.csv` 与相应 `_summary.json`。表中 tick/s 比 30 低至多 0.00030，是墙钟停止时完整 tick 取整产生的误差；四场均通过分析器的一 tick 容差门。表中内存范围来自 30 秒趋势样本；逐帧汇总的静态内存最大范围依次为 47,904/65,460/44,200/302,808 B，均无首尾单向增长。新耦合档显存中途出现过 32 KiB 波动并回落。

## 视觉评分与交付

水体 **9/10**，沿 [WATER-G2](WATER-G2_水体完成.md)：浅水透底 2、青绿深浅 2、连续岸线 2、推进浪前 2、白沫/亮纹 1。透底、岸线和浪前关键项满分；近景亮纹仍有较规则网状伪影。

沙体 **8/10**：体积轮廓 2（初始高宽比 0.847，压实塔 10 秒 IoU 1.000）、支持下保形 2（60 秒 IoU 1.000；受损/自动冲刷后局部塌落）、陡侧面光照 1（仍有物理格造成的折角及局部灰壁）、颗粒尺度 1（世界 3.3 cm、远景导数淡出，但近景颗粒对比仍较粗）、连续干湿 2（GPU 湿润→撤水→干燥时间线及三镜头四阶段）。沙与水均达到 ≥8/10 门；保形/透底/岸线/浪前满分。

最终 [70 秒一镜录像](S05_sand_coupled_sequence.avi)、[事件/命令/9 帧清单](S05_sand_coupled_demo.json)和 [近景塌坡帧](S05_demo_t600.png)展示工具挖/堆、波入、绕流冲刷、退水湿痕、趾部失稳及外侧堆积。水沙视觉状态与测点、事件和沙底差分一致。

## 保留项

旧 T08 在 SCN-03 曾一次出现约 8.6 MB、原因未定位的资源阶跃，后来多次未复现。本次同场 30 分钟未复现，逐帧静态内存范围 44,200 B、30 秒样本范围 7,700 B；**这不能证明旧阶跃原因已消除**。按计划保留“旧 SCN-03 阶跃根因未定位”为未通过的历史诊断项，不计作本次四场长稳的通过证据之外的修复结论。

运行入口：`pwsh -NoProfile -File tests/visual_phase2/run_sand_final_acceptance.ps1 -Case coupled -Mode frame -Seconds 300 -Warmup 30`；四场把 `-Mode soak -Seconds 1800` 与各 `-Case` 组合；`python tests/visual_phase2/analyze_sand_final_soaks.py`、`python tests/visual_phase2/analyze_sand_coupled.py`、`python tests/visual_phase2/freeze_sand_profile.py` 均输出 PASS。SAND-G2 按本阶段冻结门通过。
