# G2 GPU水数值

状态：[已完成]。结论仅为固定床二阶水核通过；尚未通过生产侵蚀/材料耦合、恢复生命周期、主场景铲沙/浮物体验或性能门，默认仍是一阶。

## 实现与来源

新增 `shaders/simulation/muscl/` 与 `water_muscl.gd`，实际执行h/eta/u/v的MC重构、静水压力和床源项、阶段供水限制、两次Euler与RK凸组合、GPU阶段界检查/减半重试、净通量发布及一次完成头结算。私有约8.25 MiB阶段资源由water所有，不成为第二套公开水面。`water_numerics.gd`严格校验算法身份；配置hash变化与真实调度路径变化分别有证据。

GPU使用GTX1050、Godot 4.7.2 stable steam、D3D12 Forward+；实际引擎与源码hash在每run中记录。隔离目录为 `test_output/wave_propagation/g2_workspace_01`。每个成功run的消费来源封存在 `consumed_sources.zip`，原始字段保留字节数/SHA256和实际完成时钟。完整索引为 [G2_来源索引.json](G2_来源索引.json)；汇总断言为 `g2_gate_summary_01/final_result.json`。

## 平面波与二维精度

命令：`python tools/wave_propagation/verify.py --suite water --solver muscl_mc_ssprk2_v1 --fixture task/wave_propagation/验收/water_fixture_v1.json --project-root D:/godot/project/sandcastle/test_output/wave_propagation/g2_workspace_01 --output <新绝对目录>`。已执行目录为 `g2_water_suite_01`，21个明确用例串行完成，所有原始数据及数值检查通过。

H=0.1 m、A=0.1 mm、dx=0.125 m时：

| 波长 | 两秒剩余振幅 | 相速误差 | 判定 |
|---|---:|---:|---|
| 1 m | 35.6359% | 0.2052% | ≥25%，误差≤5% |
| 2 m | 93.3337% | 0.5683% | ≥85%，误差≤2% |
| 4 m | 99.6307% | 0.2288% | ≥95%，误差≤2% |
| 0.5 m | 0.03161% | 15.7149% | 只记录，未解决短波；两秒振幅已接近f32分辨率 |

相位按G0冻结的0–1秒窗口连续解包，低于初始幅度2%的样本不用于相速；0.5 m实际有效窗口止于约0.733秒。没有把噪声地板后的相位当真实频散，也没有承诺0.5 m密集涟漪。

H=0.05/0.1/0.2 m下，λ2的测得相速依次约0.7047/0.9961/1.4082 m/s，趋势正确。A加倍的两秒幅度比例相对误差约0.00751%/0.05109%/0.10994%，低于5%门。Z向和斜向短波按GPU接受dt逐步重放完整二维CPU算子，场误差符合C03；空间阶依据为G1同物理域四档CPU细化，最细X/Z约2.052、斜向约2.030。没有宣称生产GPU网格已切换或完成GPU细网格档。

## 静水、强输入、净通量和时钟

平床、斜床、台阶、湿干岸线和障碍静水短测无负水深/非有限场，真实发布视图与权威最终场一致。干床与近干溃坝按实际接受dt重放CPU场，在冻结强波容差内；不把短测宣称为五分钟长稳。

`g2_net_flux_01`从实际GPU最终h、U2、两阶段原边/donor及公开四向flux重建最后接受子步，最大深度差约1.39e-8 m，低于2e-6 m；各阶段净flux的直接重算在预先的8epsilon舍入界内，共享边不会两侧同时正出流。此处是最后接受子步，不是整tick通量累计。CPU对照对一个tick的所有接受dt逐次重放，覆盖中途拒绝，不把RK阶段多算为物理步。

容量fixture使用明确的1000 m平水测试压力上限，前四个请求各接受64步、每次实际只前进约0.008077秒，status=1；随后补足实际目标时间，未以tick/30伪造。正常波/溃坝中存在真实拒绝试算，水场、接受数、时钟和audit相符。

`g2_special_03/obstacle_pulse`保留障碍面零通量及障碍内原水量，并在0.8秒测得上游反向qx约−0.000787 m²/s；初态该带qx均非负，完整CPU对照及原始序列支持真实反射，不是材质动画。

`g2_strong_edit_01/strong_shovel`在0.005 m浅水执行真实shovel_v1、policy2、speed0.25、0.15 m深/1 m笔画，确认APPLIED和零连通排水后推进；原水库存闭合，CPU最大场差约3.10e-9。`velocity_cap`实际触发131840次阶段/最终速度帽，水量不增加，CPU最大场差约5.46e-8。原有参数没有为保幅调整。

## 拒绝、计量与身份

`g2_final_diagnostics_01`使用GPU计算写入并回读验证负水深/NaN，随后实际请求tick。两种输入均触发control数值失败位16，trial原因分别精确为2/1；接受数、时间、tick、revision均未推进，原公开水场字节保持不变，终结清理及释放完成。尾部字段校验、finalize原因分类和audit只修正错误诊断，不改有效场算术；其后重新执行非法输入及静水CPU对照，数值矩阵的原版源码仍逐run保留。

`g2_roundoff_gpu_01`在实际主RD编译生产共用math/stats helper，验证允许的负舍入只修正一次并由CAS记录约1.5625e-11 m³；实质负值只置失败、不计clamp。该用例是helper单元，不冒充一次权威场修正或外部水源。

严格配置检查见 `g2_configuration_01`。同源码的一阶/二阶实例source map相同但configuration_hash不同；`g2_first_order_identity_01`实际走一阶路径无RK audit，而二阶有私有阶段/audit且接受步数不同。历史缺少数值对象的原配置仍解释为一阶且不被修改。当前MC+侵蚀明确拒绝为尚未实现能力，不能静默调用旧合并输运；T03负责接通。

## 保留的失败与剩余边界

首次shader因GLSL保留字active编译失败；初次special探针缺显式PackedByteArray类型；早期texture_update探针没有验证坏值被消费；中间诊断把负值同时泛记为非有限。均保留原目录，不改写失败。最终用GPU写入/回读、精确flags和发布不变重新验证。首次草稿shader原字节未单独封存，索引保留其hash/编译日志及缺失说明，不假称完整旧副本。

五分钟稳定性、真实海侧/侵蚀耦合、生命周期、实际铲沙远场门、现有浮物动态与720p完整负载成本仍待后续Gate；本阶段性能专项为0秒。
