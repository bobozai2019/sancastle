# 独立水动量实验

入口：`res://scenes/experiments/water_momentum_lab.tscn`。实验拥有自己的GPU状态、材质、时钟和队列。没有接入主场景，没有删除旧排水或改变默认策略。

```powershell
& 'D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' --path 'D:/godot/project/sandcastle' 'res://scenes/experiments/water_momentum_lab.tscn'
```

左键使用下拉框所选挖／填／铲，右键填沙。Space暂停／继续，N推进单个实际CFL水步，R复位。暂停时可以编辑，水量保持，速度冲量只注入一次。模式或初态切换会在旧GPU工作完成后复位到新generation。对照前先复位，再用重放按钮输入固定4m轨迹；导出按钮保存同完成态场、原始指标、命令、有效参数和截图。输出位于`test_output/water_momentum_lab/manual_<本地时间>/`。

模式：A0只改床面；A1复现现有形状工具的抬床速度公式；B使用实际床变归一的有符号有限冲量，填向外、挖向内。三组共用冻结的浅水核。B方向相对固定笔画起点，胶囊覆盖按实际折线段累积，停留不重复注入；同一直线的采样密度对照通过。曲线改变采样会改变折线几何，不宣称任意曲线完全不变。

铲为中心负瓣、世界X两侧各半正瓣的实验夹具，默认沿Z重放产生沟与两肩，不是跟随手柄旋转的生产铲工具。完整支持域必须在域内、沙厚足够；不可挖穿岩床。冲量、水量、沙账户分开记录。薄水、岛、墙、20／80cm平台和初始入射脉冲通过初态下拉框选择；所有工况无侵蚀、外加持续水源或正式碰撞/库存。

默认gain1m/s、radius.75m、最大床变.2m、编辑速度保护4m/s。B填沙默认速度约为A1的5倍，包含0.2m归一化标定的影响；不能以更强画面直接证明算法更优。挖区有新增有符号响应是另一项差别。正式工具标定与接入需要独立评估。

水深、速度、床面视图和流速箭头都读取同一发布纹理。平面拾取固定y=.5m，属于实验输入，不是正式碰撞命中回归。64²用于数值探针，默认可见实验为256²／32m域。桌面捕获工具超时的记录保留；引擎注入鼠标测试明确标为自动测试，用户手感评议未冒称完成。

## 重现验证

下面驱动会按顺序打开真实窗口，不并行运行GPU探针。每次使用新suffix，已有目录禁止覆盖。

```powershell
python tools/water_momentum_lab/run_validation.py --phase all --suffix _myrun
python tools/water_momentum_lab/verify_fields.py test_output/water_momentum_lab/numeric64_final_myrun
python tools/water_momentum_lab/verify_fields.py test_output/water_momentum_lab/numeric256_final_myrun
python tools/water_momentum_lab/audit_isolation.py
```

`short`包括小域、主域、画面/viewport输入及10次独立进程重进；`long`包括90秒低扰动、90秒详细计时、300秒固定点铲动+30秒释放、300秒扫域铲动+30秒释放。`revised`只重跑输入ABI影响的小域/主域/画面和长测，资源释放未变时复用独立生命周期证据。五分钟压力输入使用有账±.02m可逆铲，防止持续单向挖穿之后变成零操作；actual accepted与拒绝都记录。

每轮`manifest.json`记录实际命令、引擎进程退出、运行源码快照/前后hash和输出。`metrics.jsonl`保存每个完整作业的GPU状态汇总、CPU入队/录制/完成时间及原始GPU时间戳；`commands.json`保存accepted/rejected；`frames.json`的at_us用于相邻真实窗口_process回调间隔；ms是原始Godot delta，可能经平滑，不作为最终帧P95；`bins.json`保存每10秒资源和数值；`release.json`只在真实完成后自有RID退役时写出。完整场为小端RGBA32F=(bed,h,qx,qz)，悬沙单独R32F，不能把PNG当成数值证据。

GPU分段使用此Godot4.7.2 D3D12实际纳秒时间戳，除1e6得到ms。CPU异步回执往返包含帧调度，不是GPU核耗时。环境中的`driver=12_0`是API feature level；实际安装驱动版本另存`test_output/water_momentum_lab/hardware_driver.json`。

来源与接口：`reference/sources.json`、默认profile、任务验收G0/G1文档。源码与数学冻结审计见`test_output/water_momentum_lab/isolation_audit.json`；最终结果从任务执行状态和G5报告读取。早期失败、中断和被替代版本保留，不累计为最终通过。

最终输入包额外记录template_id、实际GLSL源码SHA256、输入/入队usec和完整精度世界坐标数值数组a_m/b_m/origin_m（可读Vector2字符串只是辅助）。非法模板和错误数值类型会拒绝，拒绝包无部分场修改。最终协议元数据补齐后的定向验证见packet_final_v3；不改物理核或调度。
