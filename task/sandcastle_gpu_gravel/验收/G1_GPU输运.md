# G1 GPU输运

日期：2026-10-15。范围：T01 / V01–V05、V07的独立核部分。结论：PASS。未接入main生命周期，不计G3/G4。

新增 `gpu_gravel_field.gd` 和 `visual_gravel_step.glsl`。三个操作共用一个核，通过mode=init/step/reproject区别，保持同一坐标与床面采样，避免三个文件公式漂移。状态为64×16 RGBA32F双缓冲；profile验证、确定性ID种子、depth滞回、speed平滑、q/h限速、目的地床高与湿润分类、tick去重、generation检查、独立保存回读计数与幂等release。

实际命令：同G0引擎可执行路径，`--headless --path D:/godot/project/sandcastle --check-only --script res://tests/gravel/gravel_transport_probe.gd`退出0；`--path D:/godot/project/sandcastle --rendering-driver d3d12 --script res://tests/gravel/gravel_transport_probe.gd`，修复后退出0、日志无RD/GDScript错误。

真实主RD输入为32×32人工R32F场（0.125m cell），未经权威水沙solver推进。不是CPU复写算法。完整[结果及代码hash](../../../test_output/gpu_gravel/transport_1792022428_525/result.json)、[逐步轨迹](../../../test_output/gpu_gravel/transport_1792022428_525/trace.jsonl)。33检查全PASS：

- h=0.1m、qx=0.1m²/s、response=0.5时单tick位移0.5/30m，30tick累计0.5m，符合G0冻结误差。
- 干水且残余q停留，水覆盖且q=0停留，再湿反向q后反向移动；h_on/off之间保留原wet状态，speed中点给出0.5平滑权重，off以下严格停留。
- 重贴床仅y/wet改变，xz保持；重复tick两份状态字节不变，旧generation拒绝。
- 强流边界clamp；斜坡目的地高度正确；dt=1s触发8步上限及effective_cap=1m/s，位移0.5m；两cell干带阻止跨越，记录限速次数。
- count=0/512/1024，ID布局、未用texel全零、有限值、域内与wet二元值正确；重复seed确定性及两份初始字节相等；pending清零，release成功。

首轮[原始result](../../../test_output/gpu_gravel/transport_1792022411_569/result.json)保留，原探针checks均true但RD日志出现texture_copy缺少CAN_COPY_TO，所以该run审计判定FAIL，不能引用内部pass作为成功。修复加纹理标志、检查texture_copy返回值及initial_ping_pong_equal用例后新run通过。这是资源初始化问题，普通restore式数值案例不受影响；不反写首轮结果。

限制：人工流场验证核，实际波浪/水下显示/owner保存切换/1024成本留后续Gate。主动探针回读是诊断例外；常规advance/reproject本身无位置回读，无CPU逐粒transform。
