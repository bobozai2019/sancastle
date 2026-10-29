# [进行中] T06 Godot核与短序列对照

角色：task_spec。负责人：主执行者。进度：1/4小目标。依赖：T03／G3、T05／G4；准备代码可提前，验收不可提前。验收出口：G5。

需求：R09、R12。契约：C03–C05，见[契约入口](../契约/README.md)。状态回填[执行状态](../执行状态.md)，实际结果进入[验收](../验收/README.md)。本文件描述计划，不记录运行通过。

## 输入

六核reference_set、冻结error_budget、T05参数／阶段轨迹；[旧水核](../../../shaders/simulation/test1_water_motion.glsl)、[旧驱动](../../../scripts/visual/test1_water_motion_trial.gd)仅作差异参考。

## 小目标与完成条件

| ID | 状态 | 小目标 | 完成条件 | 预期产物 |
|---|---|---|---|---|
| T06-G01 | [已完成] | 隔离探针与解码 | 确定独立正式测试路径，读取完整512×256打包状态，验证位掩码／保留位与输入身份。 | 探针场景／脚本、解码往返报告 |
| T06-G02 | [进行中] | 六核单步 | 实现并对照床面、速度、水量、平流、源汇、法线；保留B和辅助字段，逐核定位差异。 | 逐核buffer、差异与分支报告 |
| T06-G03 | [未开始] | 短序列与模式 | 按真实阶段／参数轨迹推进，比较误差累积；原位和显式ping-pong适配分列。 | 短序列报告、首差阶段 |
| T06-G04 | [未开始] | 生命周期与边界 | 验证暂停／恢复／重置、GPU完成态、资源释放及隔离边界，汇总G5。 | 生命周期／负例报告，G5报告 |

G01已有[完整codec证据](../验收/T06_codec_20261025.md)；G02已有六核双向读流小样本，完整覆盖未闭合，详见[当前记录](../验收/T06_readstream_20261026.md)；G03／G04尚未执行，不计通过。

## 执行步骤

1. 在tests/investigation或专用shader路径创建隔离探针，编码前登记准确文件范围；不要放进本任务被.gdignore忽略的目录后期待Godot自动加载。
2. 旧RGBA32F仅vx／vz／A／floor不足以覆盖B／宏观法线；旧E6083初态不是E1490输入。新的单步必须读取可靠参考集完整依赖。
3. 先单核：真实输入及受控干湿、床面台阶、域边界、钳制、B阈值两侧。失败定位至字段、坐标、阶段，不先调整增益或容差。
4. 单核通过后做短序列，逐步保存结果；固定床／输入和时钟，GPU完成边界实际等待。静态节点固化场景，可视化缩放不进入误差计算。

## 验证与失败出口

原始位和边界分支按冻结规则；连续字段含最大／P99误差、异常值、sum(A)与sum(h)。真正GPU完成后读回；暂停不推进、恢复不重复消费、重置不读旧generation。双缓冲通过不替代原位判定；正式水沙文件无本任务改动。

## 文件归属与写锁

仅登记的独立探针脚本／shader／场景及其资源、正式evidence和任务报告；禁止接线main／test1_geometry或更换正式求解器。

开始前在执行状态登记GPU／共享文件占用；完成后释放。所有必要证据写入唯一run目录，保留失败，不覆盖旧产物。

## 工具与命令

采用当前项目实际Godot二进制及RenderingDevice后端，先编译检查再短运行。执行时记录版本、源码／资源hash和实际入口；不把旧tick_completed信号当GPU完成时刻。



## 预登记独立路径

`tests/investigation/water_solver_evidence_probe/`作为独立Godot小项目，含project.godot、probe.tscn、probe.gd及shaders/packed_codec.glsl，后续六核亦仅在此项目shaders下扩展；task/tools/run_godot_codec.py管理新ASCII请求和正式evidence。先完整packed uint4 GPU解码／重编码及身份负例，不宣称六核通过。只使用独立项目缓存，不改根project.godot、main、test1_geometry及正式shader。实际Godot为4.7.2.stable.steam.ed1daf0bf；GPU运行需有窗口的RenderingDevice后端，headless只作解析检查。

G02扩展准确文件：独立项目kernel_probe.gd／kernel_probe.tscn、shaders/e1484_inplace.glsl、e1490_inplace.glsl、e1495_inplace.glsl、e1500_inplace.glsl、e1537_inplace.glsl、e1543_inplace.glsl；生成器tools/lower_dxbc_glsl.py、驱动tools/run_godot_kernels.py。原DXBC立即数取hex导出，不使用默认反汇编的舍入小数。

当前G02实际结果见[六核诊断](../验收/T06_kernel_diagnostics_20261025.md)：全部72身份已比较，但经验范围不能接受独立原holdout，故G02保持进行中。后续读取配对路线和显式派生容器小样本未替代原位验收。

当前T06-G02：快照72身份／216次逐位相同；六核小样本双向原位读流配对与独立审计通过。完整72身份矩阵中断于第48个身份，前47个三阶段完成，第48个只完成原生阶段；不接受全矩阵。GPU启动器的临时目录、用户数据和缓存须先满足项目内写入边界，再补剩余覆盖。详见[执行状态](../执行状态.md)及六核诊断报告；进度仍25/32，完整原位、短序列、生命周期与T07范围不变。
