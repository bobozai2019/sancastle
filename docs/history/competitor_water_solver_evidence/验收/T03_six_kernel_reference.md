# T03 六核参考、复制对照与受控输入

判定：T03-G02工具建设、T03-G03六核参考覆盖已完成；T03-G04预算仍进行中，G3未通过。没有Godot候选、原作运行时间轨迹或完整场景结论。

## 来源与工具

原test1为225224034 B，SHA256 `761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2`。六类原DXBC、常量和实际视图沿用G1逐核来源；每次native执行保持原程序字节、32×32×1线程、16×8×1组和同water UAV读写，常量块分别为2496、2560、2528、2544、2560、2496 B。

正式证据：

- [六核有／无前态copy执行](../../../docs/competitor/evidence/water_solver_reconstruction/t03_six_kernel_20261025_v4/manifest.json)：12组，每组3个dispatch，实际命令、起止时间、fence和完整原始读回保留。
- [规范参考集](../../../docs/competitor/evidence/water_solver_reconstruction/t03_six_kernel_audit_20261025_v2/reference_set.json)：程序、完整读依赖、前后边界、ArtifactRef、资源范围、配对证明和限定条件。机器审计192份文件hash一致，所有原生负例被拒绝。
- [复制对照汇总](../../../docs/competitor/evidence/water_solver_reconstruction/t03_six_kernel_audit_20261025_v2/derived/repeat_and_copy_summary.json)：每组全部3对重复，以及有／无copy全部9对交叉比较；原始逐字段指标不只汇总最后一次。
- [受控输入](../../../docs/competitor/evidence/water_solver_reconstruction/t03_controlled_fixtures_20261025_v1/manifest.json)和[六核受控执行](../../../docs/competitor/evidence/water_solver_reconstruction/t03_controlled_references_20261025_v1/manifest.json)：10种合成fixture，每种6核、每核3次，完整原始字节与依赖读回均保留。不能称为原游戏自然输入或连续轨迹。

构建v5的源、exe、命令及日志在六核run的sources正式保存；cl19.51.36260.0／link14.51.36260.0，实际工具文件身份见audit的toolchain.json。该构建未打印SDK include/lib的minor选择，不宣称确定SDK小版本。运行设备仍为GTX1050，LUID、vendor/device和显存见每组device.json，驱动沿用G0；后台GPU负载未全程采样，不作性能或全机空闲声明。

## 完整依赖与配对

E1484增加完整8 MiB沙SRV t0、stride16；E1537增加512×256 R16G16_FLOAT t0（紧密读回524288 B）及8192 B、stride16的空气SRV t1。复制对照开启时，water与所有SRV的GPU前态读回hash逐次等于冻结输入；输出在实际队列fence完成后才Map。关闭copy时仍执行同一恢复命令和原程序，仅移除前态复制及其必要转换，保留输出copy／fence。配对为reconstructed_controlled；没有将普通RDC post-event选择改称原游戏同次执行前态。

root signature按同register／space和类型重建，没有原serialized root-signature字节相同的声明。buffer SRV采用不可写的UPLOAD资源；纹理为DEFAULT资源且每次恢复。这个堆布局差异保留在参考边界，不能声称Unity整个执行环境已恢复。

六个程序的D3DReflect均实测返回constant_buffer_entries=0、bound_resources=0，但可执行声明仍包含完整CBV、SRV、UAV布局。工具用D3DDisassemble的真实声明检查CB0长度、u0 stride16、t0/t1类型、寄存器、sampler/counter缺席；有RDEF时才额外交叉检查。原程序没有counter声明或alloc/consume指令，不伪造counter输入。实际负例覆盖错kind布局、缺源汇资源、截断沙SRV、错常量长度、未知counter选项，均在建立输出／GPU执行前拒绝。未知counter选项的拒绝不等于已验证任意counter型shader。

六核run v4原冻结请求中hidden_counters说明错误地将拒绝归于D3DReflect；规范参考集已写明erratum，以实际可执行声明和C++代码为准。原请求不回写。后续生成器已修正该说明及run_id字段。

## 复制对照：限定原快照fixture的观测

| 核 | 有copy：三对变化格范围 | 无copy：三对变化格范围 | 跨copy模式：九对变化格范围 |
|---|---:|---:|---:|
| 床高E1484 | 0 | 0 | 0 |
| 速度E1490 | 141–181 | 95–108 | 97–156 |
| 水量E1495 | 1294–1412 | 1178–1798 | 1127–1863 |
| 平流E1500 | 536–826 | 641–786 | 469–884 |
| 源汇E1537 | 0 | 0 | 0 |
| 法线E1543 | 0 | 0 | 0 |

三个样本只能说明已观察分布。跨copy差异并未隔离为纯copy因果，因为原位模式本身也有重复变化；不将copy开关的少量输出差异直接称为扰动上界或原游戏bug。源、输入、常量、binding与线程组织固定，调度和未采样系统负载仍在限定条件内。

## 受控输入与新反例

合成fixture覆盖静水、均匀速度、干湿交界、床面台阶、域边界源项／海侧标志、钳制邻域、24位极值与2^23邻域、B上升率阈值两侧及法线阈值两侧。水布局512×256 uint4，沙布局1024×512 uint4；沙高度码按E1484实际拆位写入u2 bits12–31与u3 bits0–3，低12位障碍高度码为0。源汇障碍／空气分别为显式合成零场，不冒充捕帧payload。

干湿覆盖修正：原wet_dry fixture将名义A=.05量化为码83056，解码A=.05000028908254439、h=2.890825443885303e-7，实际为薄水／厚水交界；原run的操作及输入恢复判定有效，但不支持“真正干湿交界已覆盖”。旧原始数据不改写。已用显式码83055补取[真正干湿fixture](../../../docs/competitor/evidence/water_solver_reconstruction/t03_wet_dry_correction_fixture_20261025_v1/manifest.json)及[仅受影响六核的18次执行](../../../docs/competitor/evidence/water_solver_reconstruction/t03_wet_dry_correction_reference_20261025_v1/manifest.json)，初态65536格干／65536格湿；完整前态hash和fence均核对通过。预算选择表requests/budget_sources.json同时保留旧薄水反例及新干湿参考，不能按相同fixture名称合并它们。

B探针中央x254..257、y124..131的实际读回：名义rise .095／normal X码192得到0；仅提高收敛斜率使名义rise .105得到255；仅把normal X码192改为191得到0。每组3次、每次全部32个探针格均符合原DXBC预期。名义rise是构造依据，不替代真实指令的浮点值；完整全域输出仍保留，并未因中央探针通过而省略其他格。

高码反例必须进入预算与Godot字段规则：在packed_extremes里，E1484、E1500、E1543均有37448格A发生重新打包变化，最大解码差10.1；E1500／E1543还有18724格床码变化。原码16777215经过binary32加0.5再组装可能越过24位范围，不能假设这些核逐位保留A／床面。该极值输入的自然可达性未知，不宣称正常原游戏会出现此跳变。

E1543的稳定性也依输入而变：clamp_neighborhood三对变化25/20/11格，packed_extremes为16/23/17格，最大法线X差约0.9960784314。原快照fixture的法线稳定不能外推到这些压力输入。预算应保留逐格重复范围，并同时约束MAE、P99、最大误差及离散分支，不能将局部大误差扩成所有格的宽容差。

## 失败与修复保留

six_kernel v1、v2在床高核进入GPU前因反射常量区计数为0而拒绝；分别来自直接计数假设与过滤resource-bind-info后的假设，均未产生伪参考。v3确认反射确实全0后转声明审计，但最初正则使用RenderDoc的`cb0`拼写，SDK实际为`CB0`，也在GPU前拒绝。build v5／suite v4统一匹配真实声明大小写后完成全部参考和负例。各版源、exe与错误均保留，不覆盖成PASS。audit v2仅补齐ArtifactRef资源范围和metadata erratum，不重跑GPU。

## 实际执行入口

工具的`--help`均已执行；以下为成功数据使用的调用。构建前后各版输出均要求新目录。

```powershell
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/build_native.py --output D:/godot/project/sandcastle/task/competitor_water_solver_evidence/work/native_reference/build_v5
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/run_native_suite.py --replay-manifest D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t01_stages_20261025_v2/manifest.json --build D:/godot/project/sandcastle/task/competitor_water_solver_evidence/work/native_reference/build_v5 --output D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t03_six_kernel_20261025_v4
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/audit_native_suite.py --suite D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t03_six_kernel_20261025_v4 --output D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t03_six_kernel_audit_20261025_v2
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/make_controlled_fixtures.py --output D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t03_controlled_fixtures_20261025_v1
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/run_native_controlled.py --suite D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t03_six_kernel_20261025_v4 --fixtures D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t03_controlled_fixtures_20261025_v1 --output D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t03_controlled_references_20261025_v1
```

以上成功命令均exit0。原始执行时间、实际命令和子进程退出码见各manifest；没有将进程总时长解释为GPU耗时或模拟dt。下一步是构建逐参考／逐字段预算及其负例，在任何Godot候选比较之前冻结；预算仍null，不因本报告完成而关闭G3。

干湿修正实际调用均exit0：

```powershell
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/make_controlled_fixtures.py --output D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t03_wet_dry_correction_fixture_20261025_v1 --only wet_dry
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/run_native_controlled.py --suite D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t03_six_kernel_20261025_v4 --fixtures D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t03_wet_dry_correction_fixture_20261025_v1 --output D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t03_wet_dry_correction_reference_20261025_v1
```
