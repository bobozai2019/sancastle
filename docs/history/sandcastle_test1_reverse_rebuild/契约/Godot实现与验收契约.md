# Godot 实现与验收契约

日期：2026-10-09。角色：contract。状态：draft，RG2冻结。

竞品业务代码不分析、不复刻。交付聚焦沙滩效果技术；堆挖、工具命令、库存账本、存档及交互复用本项目已有实现。竞品C#/IL2CPP仅用于必要视觉资源结构/参数解码，Shader/ComputeShader技术计算可逆向；未知问题不扩大为业务代码调查。

## 1. 实施边界

新样片拟用`scenes/test1_beach_sample.tscn`和`scenes/test1_beach_coupled.tscn`，公共材质/profile资源拟放`resources/test1_beach/`，显示实现拟放`scripts/visual/test1_beach/`及`shaders/visual/test1_beach/`。这些是实施期拟建路径，当前尚不存在。

复用现有`water_render_demo_v8_preview.tscn`、`water_render_coupled_v8_preview.tscn`、`scripts/visual/water_render_profile.gd`及现有GPU域能力；先查实际接口再决定继承/共用方式，不复制整套求解器。原型脚本只作source，不自动进入正式入口。

按AGENTS.md，静态节点、地形显示层级、相机、光照、材质/资源绑定和固定信号保存在`.tscn/.tres`；脚本只初始化数据、更新状态和生成确需动态的视觉对象。不得在`_ready()`重建静态沙滩/UI。

## 2. 状态与表现接口

| 字段 | 类型/单位 | 规则 |
|---|---|---|
| rock/sand/water | 同完成态GPU纹理，米 | bed=rock+sand，eta=bed+water；岩可负，沙/水沿旧非负约束 |
| momentum_x/z | 原GPU定义 | 流速/泡沫若读取须保留原单位/水深保护 |
| wetness/compaction | 原GPU字段，[0,1] | 材质映射读取，不伪造物理湿度 |
| generation/revision/tick | int | 跨代或半完成态拒绝捕图/恢复比较 |
| visual_time_s | float秒 | 完成tick驱动，冻结/恢复同相位；显示插值仅用完整态 |
| visible_bed/surface_sampling | 统一高度/法线基准 | 沙面、水面、亮纹、白沫与碰撞差异有明确解释和误差界 |
| scene_color/depth | 渲染输入 | 明确采样阶段、分辨率、色彩/深度解码；不当作权威模拟水深 |
| foam_history/instances | 视觉字段或buffer | 格式/stride/生命周期/seed/预算/恢复方式明确；不进入沙量账本 |

保持原256²、32m、0.125m/格、30Hz及CFL约束。仅当RG2证据证明需改物理输入或表示时另立决策，并重验对应守恒/碰撞/恢复；不能借视觉调整静默换域规格。

固定样片中的高沙体需由可解释地形数据或明确标记的诊断几何形成；正式可编辑沙体必须回接权威沙状态，不能用装饰塔遮掩高度场能力差距。

## 3. Profile与运行清单

优先扩展现有loader；新`test1_beach_profile_v1`或适配方案显式版本化。字段最低要求：`profile_id, schema_version, phase, source_sha256, fixture_id, seed, lighting, camera_ids, render_settings, sand, water, waves, caustics, foam, contact, capability_status, evidence_conclusion_ids, adaptation_notes`。各效果子字段在RG2逐字段确定类型、单位、范围、默认值、依赖资源和消费位置。

未知字段/版本、缺资源、启用无消费者的效果必须报错；pending禁用项不能算视觉完成。直接启动、捕图、录像和性能探针共用初始化与effective_profile，避免只有捕图好看。

每次证据manifest包括run_id、源码/资源/profilehash、实际场景、seed、实际机位/投影、实际输出尺寸、光照/曝光/色调映射、tick/visual_time/generation/revision、波包、有效开关与绑定、硬件/Godot/驱动、原始输出路径和结果。

## 4. 视觉目标与验证

RG2冻结`analysis/reference_board.md`，主参照test1，分别定位干沙、高沙体、浅沙底、深水、浪前、岛脚/陡岸和遮挡ROI。原作与Godot世界尺度/机位不同处明确标注，不用整图SSIM宣称复刻度。

| 项 | 交付要求 | 否决例 |
|---|---|---|
| 沙体与受光 | 宽沙滩、高沙体、体积明暗、连续表面、投影 | 仅平色平面、模型/碰撞脱节、大片不明灰壁 |
| 深浅水 | 浅水可读沙底，深水青蓝层次，角度响应 | 全域均匀蓝、浅水被遮死、斜向硬色缝 |
| 推进浪 | 从海向岸推进、可见起伏及连续前缘 | 固定亮线、细尖脊、长白墙、穿岸片 |
| 亮纹 | 水底的柔和组织与动态尺度接近目标 | 干地发光、画在水面、规则闭环过显 |
| 白沫 | 浪前/接触处细碎，随浪生成、迁移、消退 | 羽片重复带、硬边大白块、永久白环 |
| 接触/遮挡 | 贴合可见沙面，前景物体深度关系正确 | 干沙误白、闪缝、浪/沫悬浮或穿物 |
| 连续/一致 | 实时、冻结、暂停、恢复、转镜头一致 | 只在单帧成立、墙钟相位漂移 |

数值化测量只用于能比较的同类ROI与同输入A/B：厚度/前缘连续性、亮纹尺度、误覆盖、相位一致等阈值须在RG2结合证据冻结，不能先编造通用相似度门。旧岸线偏移/误盖等门涉及复用实现时继续有效。

## 5. 验证节奏与成本

每个候选先解析/编译检查→短运行与相关负例→同态分项对照→连续观察，证据通过后才合入。纯文档和可逆静态绑定改动不用扩展数值测试；改变GPU/地形/碰撞/保存恢复链时才跑有意义的对应回归。

RG3以完整固定沙床视觉为门。RG4整合后测有浪、堆挖、已有侵蚀的代表性负载：1080p/D3D12/GTX1050/VSync off、墙钟p99≤33.3ms、编辑可见反馈≤100ms、30Hz模拟语义；不使用隐藏窗口数据代替。吞吐按tick完成时间戳/明确窗口测量，计数端点量化误差单列；不因29.999x与30的端点差异机械重复长跑，不回写旧FAIL。

最终profile才跑三机位各300秒及30分钟活动/资源稳定性；测量探针不全量缓冲CSV污染内存读数。相关已有恢复、守恒、碰撞与旧入口回归报告一起交付，未过项据实登记。
