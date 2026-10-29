# T03 原DXBC兼容性小样本

状态：进行中。T03-G01路线决定完成；T03-G02建设已完成E1495兼容性小样本，尚未完成六核工具及其负例／观察扰动覆盖。G3未通过，数值预算null。T03-G03、G04未完成。

## 来源与执行

原test1身份、E1495完整DXBC及绑定见G1；程序SHA256 `549114c23f1921610bacaf1d9ae375814fda1fb1de492cc2a4acfc53a502c64f`。固定输入选G1保存的E1490后态，仅作为受控fixture，不声称原作E1495真实前态；输入SHA256 `eeccf7b2e8a95f72de0235f40b2a927d1d431e98bdf24594b354542f4eecb43a`，完整2097152 B。

执行器通过D3D12原样创建该cs_5_0程序。root CBV b0（2528 B有效常量、2560 B上传分配）、structured UAV u0 stride16、131072元素、原位同资源读写，16×8×1组。原程序字节未改写，也没有CPU替代参考。没有额外SRV、sampler或counter；与G1 shader声明和视图一致。

设备vendor4318（0x10de）、device7309（0x1c8d）、LUID及显存见[device.json](../../../docs/competitor/evidence/water_solver_reconstruction/t03_native_pilot_20261025_v1/raw/device.json)，对应本机GTX1050；驱动身份沿用G0。队列DIRECT，未开启debug layer。后台GPU负载未全程采样，本次不声称空闲GPU条件或性能。三个repeat每次先完整上传恢复water，再复制真正dispatch前的水字节到独立readback，执行原DXBC，转换并复制后态；同一命令列表完成后Signal，并等待对应fence，再Map读取。前后快照包围同次dispatch，归类reconstructed_controlled，不称原游戏自然执行。

## 实测与验证器修正

- [原始执行manifest](../../../docs/competitor/evidence/water_solver_reconstruction/t03_native_pilot_20261025_v1/manifest.json)：native进程exit0，三份before hash逐位等于固定输入，三个完成fence分别达到1、2、3；原字节、root signature、程序、CB、C++源和exe均已保存。
- 原始Python验证器exit1：错误假设水量核u0/u1速度位逐位保留。该失败报告不覆盖。查看原DXBC的64–90、101–120指令并以FXC `/dumpbin /Lx`取得十六进制常量后，确认原核对已有整数码也执行`uint(float32(code)+0.5f)`，会使超过2^23的部分奇数码进位。
- [修正字段规则后的证据复审](../../../docs/competitor/evidence/water_solver_reconstruction/t03_native_review_20261025_v2/manifest.json)不重跑GPU、不改容差；由指令导出的打包预测精确解释4586格X速度码、17809格Z速度码变化，所有word0/word1及床面／高位保留字段检查差异0。床高本fixture码值没有进位；极值和溢出仍需受控输入。review v1保留；v2只修正FXC实际输入路径的来源记录并提取共享打包函数。
- 三次真正相同输入的输出两两不同1548/1271/1614格；A最大差分别0.01156455347326718、0.01156455347326718、0.009865689865689475，速度码和B两两相同。该观测限此设备、fixture和执行器，尚未分离线程调度／观察扰动，不作为通用噪声上限或Godot容差。
- [支持资料与实际负例](../../../docs/competitor/evidence/water_solver_reconstruction/t03_native_support_20261025_v1/manifest.json)：归档build命令、输出、源和exe来源；截断水输入和错误DXBC头均由原生程序拒绝，exit1，GPU资源和输出目录建立前终止。完整六核的错binding／缺资源／counter恢复负例仍待扩展。

首个build记录vcvars hash及源／二进制hash，未输出具体cl路径／版本；已改build脚本，使后续扩展构建输出where cl/link及/Bv。该工具链记录限制不等于后端执行失败，G3前必须补齐。必要build日志已迁入正式support目录，清空work不丢失唯一资料。

## 实际命令

build、审计及support归档均exit0；初始pilot wrapper因错误保留位假设exit1，内部native exit0。下列新输出不可覆盖已有目录。

```powershell
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/build_native.py --help
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/build_native.py --output D:/godot/project/sandcastle/task/competitor_water_solver_evidence/work/native_reference/build_v1
D:/godot/project/sandcastle/task/competitor_water_solver_evidence/work/native_reference/build_v1/water_reference.exe --help
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/run_native_pilot.py --help
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/run_native_pilot.py --replay-manifest D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t01_stages_20261025_v2/manifest.json --executable D:/godot/project/sandcastle/task/competitor_water_solver_evidence/work/native_reference/build_v1/water_reference.exe --input D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t01_stages_20261025_v2/raw/e1490_uav0.bin --output D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t03_native_pilot_20261025_v1 --repeat 3
```

FXC实际完整命令与hash见support的derived/provenance.json。复审及归档实际调用：

```powershell
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/audit_native_pilot.py --help
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/audit_native_pilot.py --input-run D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t03_native_pilot_20261025_v1 --hex-assembly D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t03_native_packing_20261025_v1/e1495_hex.asm --output D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t03_native_review_20261025_v2
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/record_native_support.py --help
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/record_native_support.py --build D:/godot/project/sandcastle/task/competitor_water_solver_evidence/work/native_reference/build_v1 --pilot D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t03_native_pilot_20261025_v1 --assembly D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t03_native_packing_20261025_v1/e1495_hex.asm --output D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t03_native_support_20261025_v1
```

## 下一项可区分实验

扩展执行器支持床高核的8 MiB沙SRV和源汇核的512×256 R16G16_FLOAT障碍纹理／8192 B空气SRV，并保留原位UAV、原常量和阶段次序。增加开启／关闭前态copy的单变量对照，比较相同输入恢复下的输出分布与扰动；建立各核受控边界、干湿、钳制及B阈值样本后，再冻结数值和离散分支预算。不得将本次单核兼容性改称六核参考已齐，也不得以扩大容差掩盖未匹配位段。
