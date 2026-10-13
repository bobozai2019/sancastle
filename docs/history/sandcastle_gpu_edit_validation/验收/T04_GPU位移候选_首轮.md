# T04 GPU位移候选：首轮

日期2026-10-11。角色acceptance_evidence。T04 G01进行中，G3不放行。本轮验证GPU策略计算，未验证真实沙命令后的原生纹理事务或连续求解。

## 实现与证据

新增`shaders/simulation/edit_validation/water_displace.glsl`，测试入口`tests/edit_validation/water_gpu_probe.gd`。固定输入old/new bed、h、悬沙、hu/hv与障碍上传为**测试初始化缓冲**；GPU独立candidate与scratch不写输入。只有取证入口全量读回candidate，不能当生产热路径。receipt是本探针专用128byte布局，尚未映射编辑事务公共回执。

GPU四邻BFS只连编辑前h>0.001、obstacle<0.5格，标签与队列容量N²。遍历完成后按全域行主序构建组件链表，需求/容量、携水悬沙/动量和残差结算均在GPU；不会按每组件扫描整个全域，分裂为大量小池也无N²×组件数的扫描。输出非有限/负水沙或量超预算时拒绝并将整个候选恢复为输入四字段。

[024846最终40项报告](../evidence/20261011_024846_scenes/water_gpu_probe.json)通过；[024712首次40项](../evidence/20261011_024712_scenes/water_gpu_probe.json)也通过，但非法Inf输入的诊断JSON出现NaN→null warning，后续明确将拒绝样本的量闭合标为not_applicable，仍通过raw bytes验证拒绝恒等，没有把非法数值变成0。shader的source/实际SPIRV大小和hash、引擎启动参数、源码hash、每例input_f32、candidate_f32、receipt和oracle_f64四字段、artifact_index都在运行目录。

每域20例：无编辑；20/80cm沙帽；干地；零容量/部分容量；深水/小量/挖沙；携水悬沙与初始流；障碍/干地隔池；圆顶；干湿阈值附近带流；域边；棋盘格独立池；NaN床、负水、Inf动量和负悬沙拒绝。64²有2048个棋盘湿区，256²有32768个，均完整遍历而非截断；非连通池没有混水。

测试逐格与独立float64 oracle对照、有限/非负、水沙及动量（干格损失单列）积分闭合；receipt组件数/capacity_status与oracle核对，moved与实际GPU供体减少量及oracle预算核对，retained也核对。合法候选按原水/沙预算验证；momentum诊断的单位单列m²/s和m³/s，不替代后续CFL和实际速度上限门。非法输入的status必须rejected且四字段原始bytes恒等。

部分容量样本是16×16湿区、中心abs(offset)<6的11×11供体，旧12cm水，80cm帽；两域实际moved0.042187511920929m³、retained0.184687480330467m³，capacity_status=1，未跨干区、未删余水。棋盘池供体没有同组件接纳格，moved0、retained约0.105m³。

## 失败与修正

024440脚本变量名match与GDScript关键字冲突，parse失败保留；改为within_budget。

[024452](../evidence/20261011_024452_scenes/water_gpu_probe.json)24项中13项失败，定位为残差单格集中，水量闭合但逐格分布超预算。按[ADR v1.4](../契约/ADR_位移残差逐格有界结算_v1_4.md)单变量修正逐格残差上限，水/沙容差未放宽。256²深水最大水差由0.000850665m降至9.40748e-7m；cap20由0.000116108m降至9.50701e-8m。024452原始失败不覆盖。

## 未完成

接入真实GPU old-bed快照、沙编辑候选/提交后的纹理，绑定generation/revision、audit拒绝与显示发布；禁止将该测试初始化上传当成运行时CPU全图路径。还须真实水审计负例、正常沙库存账本下的W01输入、同态连续30Hz+CFL曲线、独立速度档位以及组合。碰撞/恢复/快速命令与成本仍属T05/T06。本轮不计T04小目标完成。
