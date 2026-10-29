# RG4 实时沙滩与联合验收

状态：**用户要求全部暂停，RG4 尚未通过**。日期：2026-10-10（Asia/Shanghai）。原需返工项及成本失败保留；本报告按 [总纲](../总纲.md) 的 RG4 门槛记录正式场景，不把探针的 `PASS: collected` 当成成本验收。

## 正式配置

- 固定场景：`res://scenes/sandcastle_test1_beach_fixed.tscn`；耦合场景：`res://scenes/sandcastle_test1_beach_coupled.tscn`。二者共用 `implementation/test1_beach_release.json`。
- 沙面使用真实高度场几何、顶点受光与颗粒法线调制；静态 64×128 细沫网格存为 `.tres`，运行时仅更新随浪场。太阳投影关闭：同 tick 三机位 A/B 中主/近/掠射各只有 11/45/11 个像素的 RGB 差异超过 2（各 1280×720），保留投影却使主视角 60 秒 p99 从 30.458 ms 增至约 34 ms。场景静态配置与 test1 入口的初始化后覆盖一致，后者是因为共享预览初始化会重置阴影开关。
- RDC 中原作沙面确有阴影比较指令（见 [P02 沙体报告](../analysis/sand_report.md)）；最终 Godot 样片保留太阳受光，却省略可投射阴影。这是成本与当前构图下可见贡献之间的适配取舍，不能称为原作阴影链复刻完成。
- 此处是 Godot 适配；原作动态时序、完整沙/浪公式仍是 [RG2](RG2_结论可信度与实施路线.md) 登记的未知项。不能由本样片反推原作算法。
- 当前资源 SHA256：固定场景 `8586D29782539F48464C662CAE33A309B42425C034676C5F6EAA25F9AE4C8030`；耦合场景 `8633AE81FD3B95678D296CAC09C3B22268A0AF65EA137A845DA642C7E4B0BCD5`；耦合入口脚本 `C9B4A4D15B9FE1DF97F653DF9330A08CCF54312FA275F9D505873F850F9C0582`；profile `F07325A9EACBBFBA293E2190107E2EB21982C60A638AEF67980FAD03F61D910A`；沙 shader `0E8340B6E20E3D5A8380549995610E5A442B04524FF72E50C996B5CB4F9E7366`；细沫网格 `F343B5354AD4B18DA405BD538D79E021112F58B39D129F307D248A13261F7B1B`。前述成本长测使用旧耦合入口；工作线程版60秒成本证据另列于下文。
- 共用预览脚本 `reference_preview.gd` 的当前 SHA256 为 `E10841E9B3D6CDDE1F24CEA6ED9564C3C085408B96EEAB49C4C919289E96D43B`；只新增默认关闭的悬停预取试验开关，正式场景未启用。其有效配置/旧数值路径的17项模拟契约、3项场景集成、G04编辑和固定/耦合配对恢复均在该脚本版本下通过。
- CPU 沙域 `sand_water_domain.gd` 当前 SHA256 `449B69482A2DE6347A3562B6610507B2669BB8BCDC34CB6E15E363946866CADC`；笔刷候选格改为包围盒枚举，原距离/权重公式和顺序不变。[274例逐元素对照](../implementation/g05_brush_bounds_equivalence.json)、17项模拟契约、3项场景集成、拓扑和旧沙夹具工具操作通过；本改动尚不能使RG4成本与反馈门槛通过。
- RG3 证据引用的原固定场景和入口脚本已分别保存为 [原字节场景快照](../../../../scenes/sandcastle_test1_beach_g03_snapshot.tscn) 与 [原字节入口脚本](../../../../assets/test1_beach/test1_beach_g03_entry.gd)，SHA256 与 `g03_manifest.json` 完全一致。另有 [可运行复现场景](../../../../scenes/sandcastle_test1_beach_g03_replay.tscn)，只把脚本资源路径指向该旧脚本；RG3 其他八项依赖 SHA256 仍匹配。历史报告与原结果未回写。

## 功能与回归

| 检查 | 结果 | 证据与限制 |
|---|---|---|
| 连续浪、堆挖、沙量与碰撞 | 通过 | 正式场景 [G04 探针](../implementation/g04_probe/manifest.json)：三笔编辑、库存加沙量守恒约 `4e-10 m³`、64 个碰撞 chunk；包围盒笔刷修改后用 [独立目录复跑](../implementation/g04_probe_bounded/manifest.json)，结果仍通过，旧证据未覆盖。 |
| 固定/耦合保存恢复及继续 | 通过 | 最终场景/脚本重跑的 [正式 profile 配对探针](../implementation/g05_cost/release_final_pair_after_hook_manifest.json) 到 tick 600；[编辑恢复探针](../implementation/g04_probe/manifest.json) 到 tick 210，配对继续各水沙/动量/白沫 hash 相同。 |
| 旧 S06 checkpoint 严格逐位回归 | **当前两轮通过，历史间歇失败未归因** | 原脚本此前失败；[诊断](../implementation/g05_legacy_checkpoint_diagnostic.json) 显示多字段最大绝对差 `<3.1e-7`，`>1e-6` 单元为 0。2026-10-10原脚本连续两轮退出码0，其中[第二轮日志](../implementation/g05_legacy_s06_current_run.log)八字段逐位相等；[两轮子步探针](../implementation/G05_旧S06恢复分歧定位.md)完整覆盖1800 tick且逐位相等。成功不能覆盖旧失败或证明稳定修复。脚本默认路径 `D:/godot/Godot_v4.6.2/godot.exe` 当前二进制 `--version` 实为 `4.7.beta.custom_build.dff2b9bb6`。 |
| 三机位与负例 | 通过当前样片分层判据 | [正式阴影关闭近景截图](../implementation/g05_release_capture_no_shadow/close_tick_0360.png)；同 tick=360 近景消融中，前景干沙 ROI `(960,520)–(1250,700)` 与高沙体遮挡 ROI `(700,235)–(880,340)` 在关闭细沫、接触、主白沫时均为 0 个 RGB 差>3 像素。与 [无波近景](../implementation/g05_release_capture_no_wave/close_tick_0360.png) 比较，三机位分别改变 254,679/264,976/331,454 像素；无波近景关闭细沫点改变 0 像素、关闭接触层仅 3 像素。 |
| 直接启动 | 通过 | 正式耦合场景用 `godot.exe --path . --rendering-driver d3d12 --fullscreen --resolution 1920x1080 --disable-vsync --quit-after 300 --scene res://scenes/sandcastle_test1_beach_coupled.tscn`，固定场景改末尾路径为 `sandcastle_test1_beach_fixed.tscn`，各退出码0；RG3复现场景在1280×720运行300帧退出码0。 |

工作线程入口接入后，[正式 G04 复验](../implementation/g04_probe_worker_integrated/manifest.json)通过三笔编辑、库存闭合、64个碰撞 chunk、tick180→210恢复，权威水沙/动量及白沫/局部浪 hash 与旧正式 G04 探针相同；[直接启动日志](../implementation/g05_worker_integrated_direct_start.log)退出码0。用当前场景重取 [tick360三机位及消融图](../implementation/g05_worker_integrated_capture/close_tick_0360.png) 与 [无波负例](../implementation/g05_worker_integrated_capture_no_wave/close_tick_0360.png)：近景有波/无波 RGB 差大于3的像素为264,976；干沙和高沙遮挡 ROI 关闭细沫、接触层均为0像素变化。当前近景图与旧阴影关闭近景图平均通道差 `0.00000760/255`，仅1像素差大于3，支持入口迁移未改变该固定态构图。新图只覆盖tick360，不代替此前300秒时间观察。

## 可见窗口成本

环境：Godot `4.7.beta.custom_build.dff2b9bb6`、D3D12 Forward+、NVIDIA GTX 1050、真实 1920×1080 全屏窗口、VSync off。连续 wave packet 负载，模拟目标 30 Hz。`wall_p99_ms` 来自逐帧墙钟，`tick_rate` 来自完成 tick 起止与精确墙钟窗口；原始帧、tick 时间戳及有效 profile 在各 manifest/CSV 中。

| 负载/机位 | 时长 | 墙钟 p99 | 完成 tick/s | 静态内存范围 | 门槛结论 |
|---|---:|---:|---:|---:|---|
| 持续浪/主视角 | 60 s | 31.459 ms | 30.009 | 1.16 MB | [通过](../implementation/g05_cost/release_final_fixed_60s_coupled_manifest.json) |
| 持续浪/主视角 | 300 s | 31.112 ms | 29.949 | 2.71 MB | [未过 30 Hz](../implementation/g05_cost/release_oblique_300s_coupled_manifest.json) |
| 持续浪/近景 | 300 s | 21.849 ms | 30.002 | 2.69 MB | [通过](../implementation/g05_cost/release_close_300s_coupled_manifest.json) |
| 持续浪/掠射 | 300 s | 20.982 ms | 30.002 | 2.84 MB | [通过](../implementation/g05_cost/release_grazing_300s_coupled_manifest.json) |
| 持续浪 + 19 笔交替堆挖/主视角 | 60 s | 33.757 ms | 29.329 | 6.16 MB | [未过](../implementation/g05_cost/release_edits_60s_coupled_manifest.json) |
| 持续浪 + 566 笔交替堆挖/主视角 | 1800 s | 36.367 ms | 28.326 | 21.48 MB | [未过成本](../implementation/g05_cost/release_activity_1800s_coupled_manifest.json)；内存含逐 tick 缓冲 |
| 同负载、关闭逐 tick 诊断行，563 笔编辑 | 1800 s | 35.406 ms | 28.169 | 11.92 MB | [成本未过，资源健康](../implementation/g05_cost/release_activity_resource_1800s_coupled_manifest.json) |
| 90 tick 同相位编辑、无逐 tick 缓冲 | 60 s | 35.888 ms | 28.863 | 5.85 MB | [未过](../implementation/g05_cost/release_edits_uninstrumented_60s_coupled_manifest.json) |
| 91 tick 相位扫描编辑、无逐 tick 缓冲 | 60 s | 31.771 ms | 29.958 | 6.29 MB | [帧时通过、吞吐未过](../implementation/g05_cost/release_edits_phase_sweep_60s_coupled_manifest.json) |
| 91 tick 相位扫描、全程 98 笔编辑 | 300 s | 34.477 ms | 29.882 | 9.89 MB | [未过](../implementation/g05_cost/release_edits_phase_sweep_300s_coupled_manifest.json) |
| GPU 空闲后独立窗口、20笔编辑 | 60 s | 34.000 ms | 29.973 | 6.61 MB | [未过](../implementation/g05_cost/release_edits_idle_60s_coupled_manifest.json) |
| 同条件、无编辑且输入计数为0 | 60 s | 37.172 ms | 29.999917 | 1.09 MB | [未过](../implementation/g05_cost/release_wave_idle_60s_coupled_manifest.json)；tick端点量化差 0.000083 Hz |
| 同编辑负载，仅设置引擎60 FPS上限 | 60 s | 41.976 ms | 29.179 | 5.96 MB | [未过且更差](../implementation/g05_cost/release_edits_cap60_60s_coupled_manifest.json) |

主视角 300 秒的 [tick 时间戳](../implementation/g05_cost/release_oblique_300s_coupled_tick_timing.csv) 有一次 tick 8370 的 631.053 ms 完成延迟，出现在约 269.7 秒；该事件足以解释约 15 tick 的窗口吞吐缺口。尚未证实是项目工作还是系统外部停顿，保留原始未过结论，不机械重跑同配置。

固定每90 tick编辑会保持与周期审计相同的相位；改为91 tick后，60秒 p99 从35.888降至31.771 ms、tick/s从28.863升至29.958。只改提交间隔，说明固定相位加重成本，但短窗口仍未过30Hz；300秒全程98笔编辑为34.477 ms、29.882 Hz，仍未过。两种结果均保留。

[编辑反馈](../implementation/g05_edit_feedback/manifest.json) 在持续浪、1080p 下交替执行 20 笔。按“提交到该 GPU 修订后的首个绘制完成帧”计算，首笔 247.9 ms、第二笔 110.6 ms，随后 18 笔 42.2–78.9 ms；包含冷首笔的 p99 247.9 ms，**未过 ≤100 ms**。这测的是修订号和绘制帧，不是逐像素显现时刻；前后截图已保存。首两笔命令应用阶段延迟高，需查沙影子同步与首次 GPU patch 路径。

[错开审计点的反馈复测](../implementation/g05_edit_feedback_offset/manifest.json) 仍有冷首笔 184.6 ms、其余两笔 106.2/113.2 ms，p99 未过。20 笔中17次沙预取命中、3次沙影子同步；首笔截图在编辑投影点附近 60×60 ROI 有165像素 RGB 差>3。错开审计点仍未消除首笔异常与独立编辑的长尾。

隔离的悬停预取试验使20笔热编辑全部命中，但 [冷首笔](../implementation/g05_edit_feedback_hover_trial/manifest.json) 仍210.1 ms；60秒成本相对同指针对照的 p99 从33.054降至31.377 ms，完成 tick/s从29.940降至29.680。该开关默认关闭，正式场景未启用；详见 [G05候选记录](../implementation/G05_成本候选与归因.md)。

[阶段追踪](../implementation/G05_编辑反馈阶段定位.md)修正了对“悬停预取命中”的解释：点击前没有成功预取，命中发生在提交后等待期间。包围盒笔刷把 CPU `domain.apply_tool()` 从约27–30 ms降至约0.1–1.2 ms，但 [新20笔反馈](../implementation/g05_edit_feedback_bounded/manifest.json) 的最大值仍为129.860 ms，未过100 ms。完整负载成本复测期间另一个Godot预览占用GPU约88%；同条件无编辑也只有约17.4 tick/s，本次新窗口不作为正式成本对照，保留旧门槛失败。

该预览进程已退出。独立可见窗口新测量中，[无预读回的20笔反馈](../implementation/g05_edit_feedback_current_b/manifest.json) 最大79.635 ms，[启动预读回的20笔](../implementation/g05_edit_prebootstrap_current/manifest.json) 最大88.947 ms；两者均通过短反馈门，不能据此证明预读回有效。稍早另一轮无预读回在较高并发负载下最大128.211 ms。反馈门的跨负载稳定性仍待确认；目前不能把旧失败清零。空闲GPU后的60秒完整负载结果列于上表；无编辑对照 p99 反而更高，长尾不限于编辑，详见[成本归因](../implementation/G05_成本候选与归因.md)。

[同运行逐帧邻域分析](../implementation/g05_cost/release_edits_idle_60s_edit_locality.json)进一步区分了两种尾部：20笔编辑提交 tick 及后一 tick 共119帧，其中19帧超过33.3 ms、局部 p99 68.808 ms；其余3860帧 p99 30.564 ms。无编辑对照另有62/3950帧超过33.3 ms。编辑会造成局部尖峰，同时基线运行也有非编辑长尾；不能用跨运行 p99 的大小否定编辑成本，也不能用编辑邻域替代完整场景门槛。

[沙读回工作线程入口](../implementation/G05_成本候选与归因.md#沙读回-cpu-校验工作线程候选)已接入正式耦合场景，把第2–6笔的主线程沙校验约38–40 ms移到工作线程，G04编辑/守恒/碰撞/恢复 hash 一致。回收版候选[60秒完整编辑成本](../implementation/g05_cost/release_edits_worker_sand_cleanup_60s_coupled_manifest.json)为 **36.937 ms/29.959 Hz**，仍未过完整成本；编辑邻域尖峰减少，非编辑长尾仍在。接入后的[正式20笔反馈](../implementation/g05_edit_worker_integrated_feedback/manifest.json)最大60.818 ms，本轮通过≤100 ms短反馈门；此前冷首笔200.763 ms的失败记录不回写。当前正式入口与成本候选仅注释不同，正式入口本身没有新的60秒成本通过证据。

[最终固定场景分层消融](../implementation/g02_capture_test1_beach_release/close_base.png) 在 tick0 使权威 rock/sand/water hash 前后不变。近景干沙 ROI 关闭亮纹、screen optics、planar reflection 的平均 RGB 差均为0；浅水 ROI 关闭底面亮纹约2.99/255、关闭 screen optics 约14.35/255，说明浅水底形与光学层仍有可归因贡献。

30 分钟计时窗口的健康计数为零 NaN、零负水/沙、零过载、零漏掉的脏区摘要，表现时钟与完成 tick 相符。其 [逐分钟资源分析](../implementation/g05_cost/release_activity_1800s_analysis.json) 显示静态内存的首五分钟中位数 111.06 MiB、末五分钟 120.89 MiB，显存两端均 198.05 MiB；该探针同时在内存保留 50,986 行逐 tick 时间数据，不能把静态内存增长归因为游戏资源。

[无逐 tick 缓冲的 30 分钟资源对照](../implementation/g05_cost/release_activity_resource_1800s_analysis.json) 首/末五分钟静态内存中位数 110.26/112.29 MiB，显存均 198.05 MiB。563 笔命令全部应用、待处理 0、保留 tick 行 0；健康计数全零。静态内存仍缓慢增加约 2.02 MiB，含持续增长的命令历史与分配器高水位，不能证明无限时长无泄漏；在本次30分钟窗口内未见资源失控。两次活动窗口的帧时与吞吐都未过门槛。

## 收尾状态与待完成

- 30 分钟持续浪与编辑活动计时和无逐 tick 缓冲资源对照均已完成；成本门仍未过。
- 三机位、无波、干沙/高沙体遮挡、浅水光学消融及直接启动已完成；旧 S06 当前两轮通过但历史间歇失败未归因。
- 用户于2026-10-10要求性能先放下。p99/30Hz及历史冷首笔稳定性均列为暂缓项，不再继续调参或测成本；RG4仍不标记通过。
- 旧 S06 当前两轮严格通过但历史间歇失败未归因，作为独立正确性风险保留，不以现有成功覆盖旧失败。水中大堆沙的排水饱和见[专项调查](../../../search/underwater_deposit_report.md)，原作同动作时序未知，当前正式物理未修改；它不属于上述三笔小体积编辑验收的证明范围。

| 问题 ID | 已观察事实 | 候选解释与能区分的下一观测 |
|---|---|---|
| Q-G05-EDIT-01 | [阶段追踪](../implementation/G05_编辑反馈阶段定位.md)定位沙读回后主线程校验约38–40 ms；包围盒笔刷 CPU 枚举已降到约0.1–1.2 ms。独立反馈历史有128.211 ms及候选冷首笔200.763 ms失败；当前正式入口20笔最大60.818 ms通过本次短反馈门。 | 用户要求暂停性能；若恢复，需同条件多负载冷首笔复测，不能以单次通过推断稳定修复。 |
| Q-G05-COST-01 | 原场景20笔编辑60秒先后为34.000/41.168 ms，29.973/29.935 Hz；无编辑对照37.172 ms/29.999917 Hz。工作线程回收版20笔60秒为36.937 ms/29.959 Hz，编辑邻域尖峰减少但完整门未过，远离编辑的长尾仍在。 | 性能暂缓。恢复时先用当前正式入口做完整可见窗口同配置复测，再分段记录非编辑帧的渲染线程/队列等待；历史失败保留。 |
| Q-G05-S06-01 | 旧 S06 此前到tick2700间歇出现严格逐位差异；[端点及同运行诊断](../implementation/G05_旧S06恢复分歧定位.md) 表明跨运行首差异 tick 不固定。当前原脚本两轮通过；另两轮完整1800 tick子步观察均一致且GPU字段全等。新 test1 配对到tick600通过。 | 在复现失败的同一次配对中记录逐tick子步数、GPU dispatch顺序、完成时间戳与首差异 cell，区分执行顺序和恢复遗漏。旧失败与逐位门槛不改。 |
| Q-G05-STALL-01 | 仅有浪主视角300秒在 tick8370 有631.053 ms完成延迟，窗口平均29.949 Hz；另两机位各30.002 Hz。 | 同步记录 OS 进程/驱动事件和主/渲染线程分段时间，排除外部停顿后再针对可复现的项目段处理；保留本次未过结果。 |

## 复跑

在项目根目录、可见真实窗口执行：

```powershell
godot.exe --path . --rendering-driver d3d12 --fullscreen --resolution 1920x1080 --disable-vsync --script res://task/sandcastle_test1_reverse_rebuild/implementation/probe_g05_release_cost.gd -- --profile=res://task/sandcastle_test1_reverse_rebuild/implementation/test1_beach_release.json --case=coupled --output=D:/godot/project/sandcastle/task/sandcastle_test1_reverse_rebuild/implementation/g05_cost --run-id=release_check --warmup=10 --seconds=60 --camera=oblique --wave-load=continuous --tick-timing
```

编辑成本用 `probe_g05_release_edit_cost.gd`，反馈用 `probe_g05_edit_feedback.gd`；完整参数与实际有效 profile 均记录于相应 manifest。长稳用 `probe_g05_release_soak_cost.gd --seconds=1800 --soak-packets=320`。
