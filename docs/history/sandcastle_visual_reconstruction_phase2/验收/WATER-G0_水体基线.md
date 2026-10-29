# WATER-G0 水体基线：通过

日期：2026-10-05。范围：T09.W01，固定床面的独立水体夹具。基线效果不计作 W02/W03 达标。

## 固定输入与运行

- 入口：`scenes/water_visual_fixture.tscn`；`fixture_id=water_v1`，seed `41021`，256²，0.125 m/格，32 m 域，30 Hz。
- 床面：缓岸、薄水膜、横向沙脊/沟、固定高地、浅深水；初始水量 87.091328 m³。沙和岩层只作为固定床面输入。
- 镜头：`oblique`、`close`、`grazing`；截图 tick 60、GPU revision 180、generation 1、`visual_time_s=6.0`、1280×720。
- 实际运行开关：`enable_erosion=false`、`enable_material=false`、`enable_structures=false`；对应三个耦合/结构实例均为 null。沙/岩 CPU 输入哈希前后相同：571176515 / 3482076697。
- Godot `4.7.beta.custom_build.dff2b9bb6`，D3D12，NVIDIA GeForce GTX 1050。捕图命令：`pwsh -NoProfile -File tests/visual_phase2/run_water_fixture_capture.ps1`，两次均 PASS；三张 PNG 的 SHA256 在两次运行间逐字节一致。
- 既有场景回归：`pwsh -NoProfile -File tests/run_scene_hash.ps1`，六个 64²/256² 输入哈希全 PASS。

## 完成态审计与分布

tick 60 GPU 水量 88.882243 m³，最小水深 0，无效/负水单元均 0。水量与初始值的差来自开放潮汐边界；这里只作基线记录，W04/W06 才验源汇闭合。

完成态 GPU 全域读回水深、x/z 动量；分箱及最大值见 [manifest](W01_water_manifest.json)。深度箱定义为干或 ≤0.001 m、(0.001,0.02)、[0.02,0.08)、[0.08,0.25)、≥0.25 m。速度为湿单元 `length(momentum)/depth`，箱界 0.1、0.5、1.0 m/s。固定这套探针用于 W02 光学深浅核验；不把输入床面数值当 GPU 完成态。

## 视觉基线和后续测法

- [斜俯](W01_water_oblique.png)：深浅颜色有基本层次，近岸几何边呈规则折线；高地绕流位置清楚。
- [透底近景](W01_water_close.png)：浅水中的脊/沟区分较弱，岸线台阶显眼。
- [掠射](W01_water_grazing.png)：薄水边缘呈锯齿，后续需测低角漏盖和干岸误染。
- 水五项沿用契约 0/1/2 分；同一 `tick/revision/visual_time_s` 三镜头对比。W02 比较固定深度箱、底形是否可辨及各光学开关；W03 在三张固定镜头以水深 0.001 m 的湿干界为参考，量岸线水平偏移（目标 ≤0.5 格）、干岸误染及低角漏盖像素比例（目标 <2%）。实际投影/标注方法在 W03 原型时冻结，不能只凭整体截图印象宣布通过。

这一步未实现光学、岸线、波包或白沫改造，也没有性能采样。下一步为 W02。
