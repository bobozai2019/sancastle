# G1A 基础契约冻结

2026-10-14，Asia/Shanghai。结论：G1A通过，T01五项完成；允许进入T02。基础接口/范围/判据冻结是本报告范围，GPU新刷子、材料、水与恢复实际功能均未通过本Gate。

## 冻结内容

- C01/C03：内置三刷子ID、参数白名单、4–6m四塔模板、尺寸/高度分离、256点缓存、0.125m采样、2m段、8次/帧提交、同域64 pending/单写者、正常drain与cancel区别。
- C02：256字节schema2独立magic/version/stride，int64身份无float，全部字段offset/alignment、set0/set1/binding和32字节push布局、错误/结果枚举、旧v1显式路由。
- C04：线性梯形capsule墙、水平城堡基底及0.25m落差、parabolic沟/双侧sine-ring接收、实际量/容量/两轮残差修复、有限几何权限与两级补偿归约预算。旧协议预算函数保持原样。
- C06/C07架构：完成态→完整candidate→单validate/commit→一次结算→发布/碰撞；mixed-delta水明确处理，speed=0与非零方向定义；edit header v4、backend区分、配置新目录/原始扩展hash、保存drain/恢复idle。
- C08：全部60个矩阵用例、CPU/GPU/真实UI判定层级、输入2cm/1%、逐笔局部eps、MAT 30模拟秒80%/IoU0.8固定ROI、5分钟长稳、场景两轮及10次短切换。

精确规范：[基础细目](../契约/G1A_冻结细目.md)、[机器规范](../../../tests/shape_brushes/contract_v1.json)。项目扩展另见[ADR](../../../docs/knowledge/water_sand/ADR_形状刷子_v2.md)。C05及可能新增native字段仍draft，material_profile=1仅预留，G4前不假装存在support或已保形。

## 实测证据

| 检查 | 结果 | 证据/边界 |
|---|---|---|
| 布局、参数、非有限、版本、int64、bindings、解析几何、预算及用例唯一性 | 408项PASS | g1_contract_20261014_v3/contract_result.json；纯Python规范审计 |
| 原库存不足/预留回滚、重复id、新kind拒绝、generation、NaN、取消、external64上限 | 12项PASS，无SCRIPT ERROR/ERROR | g1_contract_20261014_v2/legacy_inventory.json/log；真实scheduler CPU admission，GPU终结在G2/G9 |
| 原128字节布局/库存向下舍入/结果身份/单位/有限/预算 | 18项PASS，无SCRIPT ERROR/ERROR | g1_contract_20261014_v2/contract_probe.json/log |
| 60个MVP矩阵条目 | 唯一ID、全部13个family覆盖 | v3/case_catalog.json；执行入口逐项标not_implemented_at_G1A |

机器证据根目录：`D:/godot/project/sandcastle/test_output/shape_brushes/`。spec SHA256=`d01f6081c8efe3d268d10b32a8c08c0f9ff605cd20672ffb2445c5774262854c`，源码/文档/旧消费者/工具身份及命令见v3/manifest.json，产物hash见artifact_index.json。

纯数据独立参考：墙和沟通过20000步中点积分复核解析公式，不以GPU实现逐行复制；容量分配CPU用高精度bisection water filling，未来GPU可用固定序饱和再分配。binary32预算示例：

| before/Δ/count | ideal m³ | binary32实际m³ | eps_sand m³ | eps_transfer m³ |
|---|---:|---:|---:|---:|
| 1m/+0.3m/128 | 0.6 | 0.5999999046325684 | 7.6294104474e-7 | 1.5258820895e-6 |
| 8m/+1e-5m/128 | 2e-5 | 1.9073486328e-5 | 3.8246972656e-6 | 7.6493945313e-6 |
| 1m/−0.15m/256 | −0.6 | −0.5999999046325684 | 1.2397787486e-6 | 2.4795574973e-6 |
| 0.01m/−0.01m/32 | −0.005 | −0.004999999888241291 | 1e-7 | 2e-7 |

这些eps由触及格、原/后厚度ULP、绝对变化量预先计算，非运行FAIL后调宽。水预算待同公式使用实际water联合域，不能复制沙eps作为任意水许可。

## 实际命令

```powershell
python tests/shape_brushes/check_contract.py --output D:/godot/project/sandcastle/test_output/shape_brushes/g1_contract_20261014_v3
& 'D:\godot\Godot_v4.6.2\godot.exe' --headless --path 'D:\godot\project\sandcastle' --script res://tests/shape_brushes/legacy_inventory_contract.gd -- --output=D:/godot/project/sandcastle/test_output/shape_brushes/g1_contract_20261014_v2
& 'D:\godot\Godot_v4.6.2\godot.exe' --headless --path 'D:\godot\project\sandcastle' --script res://tests/edit_validation/contract_probe.gd -- --output=D:/godot/project/sandcastle/test_output/shape_brushes/g1_contract_20261014_v2
```

以上均exit0且日志检查无错误。旧contract_probe仍观察到纯CPU ToolCommandQueue会接纳NaN radius，没应用该命令；现有真实GPU scheduler先finite拒绝，新增schema同样必须前置严格验证。T01不改旧CPU语义，不把该缺陷写成已修复。

## 失败保留与遗留

g1_contract_20261014_v1留有自建探针的类型推断失败日志、第一次mock缺shutdown的日志与结果；该轮的JSON true不作Gate依据，实际日志含SCRIPT ERROR。补齐类型和生命周期stub后在新v2运行无错误，主生产代码未改。另一次调用旧probe未先创建输出目录，FileAccess空导致store_string失败并由工具结束该进程；该早期日志之后已被成功重跑同路径替换，原工具返回含失败记录，不能以当前g1_contract_legacy.log冒称该次成功。最终验收只引用上述独立v2/v3输出。

无真实GPU新增字段/候选/材料/水/first_visible/成本证据，因此G2–G9未验。T02须创建静态brush_lab和runner，显式实现资源与路由，先做dry/no_change/失败回滚/无编辑负例；不将case_catalog未来命令当运行结果。G4若新增材料状态，补C05/native双槽及输运、破坏/衰减、恢复ADR并重跑受影响G2/G3。旧性能FAIL、严格恢复未知及暂停旧任务保持原状态。
