# 当前主场景堆挖卡顿诊断

2026-10-11，独立新诊断。生产场景、脚本、shader、profile均未修改；历史性能FAIL、G5未完成、T06-WARM-001及600ms等待线索保持原判。

## 结论及证据边界

当前短测主要 GPU 编辑成本在 **E3水位移和速度归约**，沙笔刷本身很小。完整事务又串行等待回执、发布、局部碰撞读回和两个物理帧，造成约100–140ms单笔反馈。密集拖动还出现约300ms排队及碰撞未完成时拒绝新采样，完成反馈最大约400ms。

这些是当前配置的定位结果，不是优化验收，也不能解释所有历史长尾。此次未复现约600ms帧，未采集新native栈；不能宣布与历史D3D12帧复用fence等待同因或已解决。没有开展竞品逆向。

| 陈述 | 可信度、定位与反证 |
|---|---|
| E3水位移index7和速度归约index6占本窗编辑GPU计算绝大部分 | C3，本次short_detailed/trace.json按ticket的GPU start/end时间戳。48笔全部成对：挖/拖各23个candidate/commit pass，填各12个。GPU总和与CPU阶段等待分别计算；并非总延迟推断。未知驱动内部调度、渲染GPU时长及实际显示扫描时间。 |
| 单workgroup、lane0顺序全域归约是高成本结构的候选解释 | C2，实际绑定shader及时间戳一致；gpu_water_editor.gd:101对index6/7派发(1,1,1)，water_velocity_prefetch.glsl:22/28对65536格分1024块、lane0顺序累加。water_packed_cached.glsl:169起遍历湿分量和多轮容量/守恒归约。没有更改workgroup数做因果A/B，不能把所有时间独占归因给某个循环或内存带宽。 |
| 填沙比挖沙的index7更重 | C3观测/C2源码解释，填约27ms、挖约12ms；抬床产生位移需求时执行更多分量处理，而demand=0分支在shader:200跳过后续轮次。没有逐分量计数，本次未另读water receipt[27]，不能声明每笔已证实使用packed成功路径、排除全部回退。 |
| 连续输入的串行排队与碰撞时效限制增加交互延迟 | C3，dense_drag/trace.json：32次输入调用，18笔准入且成功终态，14条collision_pending；队列最大3，输入→dispatch最大299.708ms。代码beach_interaction_entry.gd:168及gpu_entry.gd:126–156支持。只覆盖固定轨迹，不能外推所有速度与位置。 |
| 本窗CPU拾取、准入及形状替换不是最大的阶段 | C3，本次基线拾取最大0.052ms，输入处理最大0.495ms，paused形状替换最大3.836ms。live替换包含正常tick碰撞批次，密集拖动曾到16.398ms，不能说碰撞完全无成本。回执callback→settle包含deferred调度，不是CPU结算独占时间。 |

## 配置、同态与机器负载

Godot 4.7.2.stable.steam.ed1daf0bf；NVIDIA GTX1050，驱动32.0.15.8183；i5-9300H。真实可见1280×720、D3D12/Forward+、VSync=1（启用）、max_fps=0、物理60Hz、模拟1/30秒。保留当前主场景默认VSync，不能直接与历史1080p/VSync关闭窗口比较性能。

真实入口scenes/main.tscn与beach_recovery_entry.gd；固定StagedSlope、CompensatedCapacity、PackedRuns、CachedCapacity、PrefetchVelocity，E3、0.25m/s、80自动浪、侵蚀开启。SkipIdleComponents、bounded collision、shape复用保持关闭。手动波浪没有额外触发。实际渲染profile hash、编译后的组件配置记录在short_detailed/trace.json.configuration.effective_compilation，不用旧lab入口替代main。

相机(-6,6,10)看向原点，完整transform在trace；世界(-2,0,0)投影到(555.7765,383.1191)，首次真实碰撞命中(-2.076786,0.11518,0.191966)。圆笔刷半径0.3m、strength1、seed101，点击0.015m³；拖动按当前距离/0.75m换算实际amount，逐笔命中、量和tick在trace中。

初始化暂停，推进2tick；另在世界(2,0,0)投影位置真实挖0.20m³，实际库存0.1727801263m³，再保存原生完成态。每个用例暂停并排空后恢复该检查点，等待碰撞及两物理帧。三次运行生成的origin.scgpu完全相同：SHA256 `6a2a5dfc52321cf76f5d4de281c4edb9cada97cd060d8403a7d61d6a766ad706`；运行配置源码签名相同，各用例begin_tick=2。没有采用不稳定60tick预热。未在每次restore后独立读取十字段作逐位复核，本次恢复依赖现有原生恢复校验；不新宣布T06-WARM-001已解决。

live各用例后续tick会随编辑等待不同而分岔，这是不同工作负载的诊断，不是算法收益的正式同态A/B。每窗3秒、8笔、间隔300ms；密集拖动32采样、间隔50ms、每次屏幕右移3px。使用真实input handler与PhysicsRayQueryParameters3D拾取，但由脚本合成调用，不包括操作系统鼠标投递延迟和GUI事件分发时间。

用户Godot编辑器PID21316全程保留；本任务6568、17116、14280均自行排空释放退出。没有其他Godot/RenderDoc/Blender任务进程参与这三次短测。GPU计数仅在详细窗中采3秒，目标PID17116的GTX graphics引擎读数约16.8–74.9%；还观测到PID9996的另一适配器3D活动约1.3–3.6%，身份未追踪。不宣称整个桌面GPU零外部负载。详见hardware_load.json、gpu_load_samples.json。

## 帧与逐笔阶段耗时

以下来自short_baseline，未开启GPU时间戳；仍开启少量已有CPU阶段/碰撞时间字段，数据在内存累积后写盘，并有一次额外拾取计时。它不是完全无观测的正式性能验收。帧为SceneTree回调之间的单调时钟间隔，p99取nearest rank；每窗仅约185帧，不外推长窗。逐笔8样本的p99等于max，表列中位数。

| 用例 | 帧p99/max ms | 输入→dispatch | dispatch→receipt | receipt→publish | publish→collision | collision→physics1 | physics1→physics2 | 输入→终态 | 输入→发布后post_draw |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 无编辑/运行 | 25.911/27.873 | — | — | — | — | — | — | — | — |
| 挖沙/运行 | 48.512/50.983 | 0.050 | 51.788 | 4.123 | 35.573 | 14.013 | 16.575 | 121.282 | 55.828 |
| 填沙/运行 | 65.385/69.542 | 0.046 | 67.793 | 4.427 | 31.972 | 7.194 | 11.294 | 129.324 | 71.759 |
| 拖挖/运行 | 49.321/51.225 | 0.047 | 52.233 | 4.484 | 35.619 | 12.943 | 16.680 | 121.235 | 55.857 |
| 挖沙/暂停 | 41.177/45.180 | 0.049 | 57.470 | 9.384 | 13.456 | 6.722 | 13.740 | 104.502 | 66.769 |
| 填沙/暂停 | 57.259/61.333 | 0.051 | 73.644 | 8.549 | 13.161 | 6.537 | 9.726 | 111.574 | 82.260 |

各列独立中位数不可相加当作某一笔总耗时。每笔完整phase_us、spans_ms、kind/shape/amount/requested_tick保存在analysis.json.commands。所有准入均有成功终态、没有挂起，released=true。

局部高度读回request→render callback的基线中位数：live约27ms，paused挖18.183ms/填17.384ms；含GPU排队、打包和下载及callback调度，不是纯GPU copy耗时。打包GPU pass在详细窗通常约0.016–0.020ms。形状替换paused中位数2.891/2.672ms、max3.836/3.615ms；live常规与编辑混合批次中位数约4ms、max6.750ms。applied_stage_usec保留每chunk的queued/request/callback/applied单调时间，可复核批次与主线程延迟；跨阶段在途读回可能重叠，不重复相加。

GPU回执callback→CPU settle基线live中位数约0.7–0.8ms，paused0.326/1.049ms；是deferred调度与结算合计。dispatch时间是main发起时刻，尚未独立观测render线程真正开始dispatch，因此dispatch→callback也含render排队、GPU执行、异步下载。完成态发布约4–10ms含帧轮询与render队列，未测其独占执行成本。physics两次等待包括引擎调度，不能叫作物理计算用时。post_draw是发布之后第一次CPU绘制提交信号，未验证实际屏幕scanout，也未做逐像素变化测量。

## GPU执行与CPU等待分开

short_detailed在每次恢复后的新solver启用已有capture_timestamp，同时采collision与正常tick pass；没有附加大规模GPU字段读回。其帧、替换和反馈较基线有扰动，不能当无诊断性能标准。只报告分段执行定位，不把不同窗口的时间相减当某一笔的纯等待。

| 详细用例 | candidate+commit GPU总和范围 ms/笔 | 其中沙笔刷GPU总和 | 水位移index7中位数/max | 速度归约index6中位数/max |
|---|---:|---:|---:|---:|
| 挖沙/运行 | 24.422–28.811 | 0.395–0.458 | 11.893/13.932 | 12.050/14.262 |
| 填沙/运行 | 39.099–46.483 | 0.121–0.144 | 27.162/31.962 | 12.017/14.218 |
| 拖挖/运行 | 24.430–27.524 | 0.419–0.465 | 11.893/13.927 | 12.054/12.977 |
| 挖沙/暂停 | 24.429–28.893 | 0.391–0.507 | 11.852/14.013 | 12.054/14.209 |
| 填沙/暂停 | 39.118–45.924 | 0.121–0.165 | 27.087/31.531 | 12.050/14.067 |

总和排除后续index4纹理发布、正常tick和碰撞pass；同一命令ticket配对，无missing pair。完整gpu_pairs还保留CPU提交时间，与GPU时间分栏。正常tick单pass一般低于0.15ms（有多个substep，不能据此宣称整个tick低于0.15ms）。本窗不存在某单编辑pass独占600ms的证据。

## 密集拖动

dense_drag未开启GPU时间戳。18笔全部status1；14采样因collision_pending拒绝；队列最大3。帧p99/max43.869/48.526ms，3秒推进30tick（初始2→32），无编辑窗推进89tick。排队中位数198.529ms/max299.708ms，输入→终态中位数298.946ms/max399.762ms，输入→发布post_draw中位数265.693ms/max366.802ms。窗口结束后额外排空约121.981ms。逐笔排队证据与input busy、pending帧记录可复核。

这说明“拖动感觉一卡一卡”包含采样被拦截和已准入命令逐笔等待；不全是某个超长画面帧。队列未满64，不能误判为容量上限拒绝。拖动距离增加时当前处理路径会折算更大请求量，不能通过随意丢笔减量破坏库存与沙量契约。

## 按证据排序的改善建议与下一步区分观测

1. **先针对water index7与index6做独立候选。** 前者约12/27ms，后者约12ms，是最大的已测GPU成本。先在同一原生origin与相同暂停命令上用E3/C1/D2/B0单变量策略诊断，测receipt状态、pass及frame关系；再审查单workgroup顺序归约如何降低等待/访存而保留冻结算术次序、预算和回执。多workgroup或并行求和会改变浮点次序，不能直接作为无损替换。历史SkipIdleComponents可以作为候选线索，但本次没有启用或补齐验证，不建议直接接main。
2. **连续拖动准入与排空周期。** 先统计真实鼠标采样轨迹，设计保留累计体积、路径和库存预留的笔段合并；在独立候选验证命令语义及碰撞时效。当前每笔要等collision和两physics_frame才允许下一笔，候选可区分“CPU已结算/画面已发布”和“碰撞可拾取/可继续”，但改变完成语义须逐项重验generation、账本、暂停及恢复。不能直接删除两次等待或使用旧碰撞无校验拾取。
3. **异步回执与碰撞队列。** 已测pause读回约18ms、live发布→collision约32–36ms，而GPU打包很小。下一探针增加render dispatch进入/退出、download申请与callback、main settlement进入/退出的独占计时；如有长帧，捕当前active线程栈或ETW队列时间轴，区分VSync、frame reuse fence、资源创建和下载调度。保留当前主场景，VSync开/关用同origin单变量观察，不预先归罪600ms历史fence。
4. **碰撞形状创建放在后面。** 普通笔刷仅几ms，shape复用/bounded selection可减少次要成本，但不能代替水GPU成本与事务等待的处理。密集窗替换有16ms峰值，先按chunk数量与物理shape注册耗时分开再选候选；既有边界几何契约不变。

以上为后续具体方案，尚未改生产算法，没有承诺收益数值。不新增正式300秒、三机位或长稳结论；旧标准与FAIL保持。

## 复现与证据

工具：[main_probe.gd](../../tools/edit_stutter_diagnosis/main_probe.gd)、[analyze.py](../../tools/edit_stutter_diagnosis/analyze.py)。在新的空输出目录执行（路径英文）：

```powershell
$diagDir='D:/godot/project/sandcastle/test_output/edit_stutter_diagnosis/new_run'
New-Item -ItemType Directory $diagDir
$diagArgs=@('--path','D:/godot/project/sandcastle','--rendering-driver','d3d12','--resolution','1280x720','--log-file',"$diagDir/godot.log",'--script','res://tools/edit_stutter_diagnosis/main_probe.gd','--',"--output=$diagDir")
Start-Process 'D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList $diagArgs
# --后追加--detailed采GPU；另一个新目录追加--dense测密集拖动。
C:/Python313/python.exe tools/edit_stutter_diagnosis/analyze.py $diagDir
```

先等日志DIAG_COMPLETE，不能在文件写完前分析。自动退出只释放本探针自己资源。默认保持当前VSync与max_fps。窗口启动后不动相机、不手工编辑；每个恢复节点不计入3秒窗口。

证据根：[test_output/edit_stutter_diagnosis](../../test_output/edit_stutter_diagnosis)。short_baseline、short_detailed、dense_drag均保留origin、trace、analysis、owner、log；详细窗保留visible_main.png。baseline的probe_source.gd按已记录工具编辑序列重建，明确不是运行时导出的源码快照；详细版在恢复后额外启用GPU计时并保存截图，最终工具追加dense选项，后二者保留启动时副本。版本差别不隐去。manifest.json记录所有证据/工具/引擎hash；source_verification.json核对三次实际生产签名一致，419项源码/资源结束时hash均相同。compile/godot.log为初版check-only，实际三个可见运行完成也验证最终使用版本可解析。旧历史证据仅摘要与小型dump可用，不重建已删除约22GB数据，也不把索引当全量字节可用性。
