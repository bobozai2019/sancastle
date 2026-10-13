# P03 实施映射（RG2 冻结输入）

日期：2026-10-10。冻结的是作用链、验证口径和改动边界；数值profile需 P03 按 A/B 固定后另行冻结。原作单帧场景单位不能直接当本项目米制。参照 [目标板](reference_board.md) 的主视角与近景/掠射视角。P0 每层均有可执行替代；未知原作公式不阻断样片。

| 层 | 证据/资源 | v8复用与缺口判断 | P03处理与拟改文件 | 单变量验证/否决 |
|---|---|---|---|---|
| 构图、体积沙床 | C-SAND-GEOMETRY；5006/5018/5030 VSOut | v8已有256网格、estuary_branched_v1床面与相机入口；是否能形成参考中的高沙体**尚未同机位实测**，先定为构图/几何待测 | 新建固定样片场景 `scenes/sandcastle_test1_beach_fixed.tscn`，继承v8入口并固化相机、太阳、沙体基线；必要时新增床面profile，不改旧v8 | 同光照冻结模拟，只换初始沙床；主/近/掠射视角检查体积、侧面法线与阴影。若高度场无法表达目标，先记录具体轮廓差再增固定模型 |
| 沙质、干湿 | C-SAND-MATERIAL；Sand纹理617 C3，材质PathID20 | `reference_coupled_bed.gdshader`已有床面材质/湿度能力；粒度、暖色、坡面受光是否匹配未验证 | 以新profile调整或在 `tests/visual_water_alignment/prototypes/reference_coupled_bed.gdshader` 加受控参数；默认不改权威湿度/沙量 | 同态只切沙色、细纹、湿映射其一，床面hash一致；转镜头纹理不漂移，陡坡仍有光照层次 |
| 水底亮纹 | C-CAUSTICS-BOTTOM；t4=1105，包内Caustics候选 | v8已有 `caustic_fold_v1.png` 和 `fold_caustics`；与目标纹形未按相同曝光/ROI验证 | 保留底面单层亮纹，按Q-CAUSTICS-01查证后在新profile或底面shader调整；不复制到水面 | 关底面亮纹仅底面线条消失；干地不亮，浅水底形仍清楚，线宽/分叉/柔度合适 |
| 浅水、深水与法线 | C-WATER-GEOMETRY / C-WATER-OPTICS；WaterNormal2D 681 C3 | v8已有eta法线、screen optics、planar reflection、深度写入；是否过度蓝暗/折射错位需同状态检验 | 新profile沿用 `reference_water_local_front.gdshader`，仅针对证实的缺口增参数或取样回退；共享完成态床面/水面 | 分别关法线细纹、折射、深度衰减、反射；浅水透底、深水转蓝、前景遮挡不被拖入水中 |
| 推进浪 | C-WATER-GEOMETRY；Q-WATER-01 C0 | v8 `local_front` 已实现；原作波速未知，先量现有浪前几何和岸向推进，不能仅调白色 | 新样片profile/相位参数；如几何不足，局部修 `reference_water_local_front.gdshader` 与数据入口 | 先纯色水面连续观察多包入退浪，检查截面、岸脚和高低差；不得出现静态白墙 |
| 细碎白沫 | C-FOAM-INSTANCES / C-FOAM-COMPUTE；139582→139575→6196 | v8 `main_foam` 有面内泡沫，`foam_splats` 仍pending；目标有独立水平细片，需先消融确认缺口来自几何还是着色 | 固定场景独立泡沫表示，优先现有泡沫实例能力；若不足再新增小片场景/资源及由统一表现时钟驱动的脚本；不套用29,950实例预算 | 主浪源和岸脚源分别开关；尺寸、密度、深度遮挡、推进/衰减及60秒连续观察；避免大片混白 |
| 岸脚接触 | C-FOAM-INSTANCES / A-GODOT-DYNAMICS；Q-FOAM-01 C0 | v8 `shore_contact` pending；需要共享可见沙床与水面阈值，不能永久画环 | 新profile接触参数及必要 `reference_water_local_front.gdshader`/新薄片输入，统一generation与时钟 | 干沙/无浪无白环；陡岸、障碍脚、近景无悬浮/穿岸，关接触源时主浪泡沫仍存在 |
| 实时模拟与编辑 | 项目旧守恒、碰撞、恢复契约；A-GODOT-DYNAMICS仅适配 | `scenes/water_render_coupled_v8_preview.tscn` 与GPU域/编辑链已有；旧实现验收是回归起点，不计新任务完成 | RG3后新建 `scenes/sandcastle_test1_beach_coupled.tscn`，继承固定样片可共享的视觉资源并接现有状态；若公共接口变化先更新契约 | 堆沙→挖沟→浪覆盖→退浪；视觉开关前后权威字段hash相同；相关守恒、碰撞、暂停/恢复、真实窗口成本回归 |

## 执行约束

每次固定 seed、tick、generation、相机、有效profile和源码/资源hash，只改变一个因素。先看形体/输入，再着色，再合成与曝光。P03 G01–G03 固定床面闭环后才接实时模拟；现有v8的 implemented 标记仅证明代码能力存在，不是目标视觉通过。`Q-FOAM-02` 的独立重放差分不能拿来调白沫覆盖预算。所有动态数值属于 Godot 适配，须连续观察后记录，不写成原作参数。
