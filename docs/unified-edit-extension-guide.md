# 统一编辑玩法扩展

现有入口使用场景内固定的 UnifiedEditRuntime。玩法声明通过 profile 注册表冻结为数据，输入只提交 Intent；Pipeline 按队列顺序录制编辑、水 tick 和显示工作。域恢复只构建同一 Pipeline 类的新候选，两个场景内高度消费者槽负责原子换代。

## 仅配置新增玩法

1. 在 `assets/unified_edit/` 新增 ToolProfile `.tres`，script 必须精确绑定 `scripts/simulation/unified_edit/tool_profile.gd`。从现有合法 operation/shape/destination/material/water/stroke 组合选择，不为工具增加 executor、shader 路径或 Callable。
2. 使用唯一 profile_id、递增 version、带单位的 defaults/ranges，以及已验证能力范围内的 allowed_water_policies/allowed_material_policies。策略2/3允许speed_m_s；策略0/1要求为0。目标高度/搬运使用公共 BEGIN/sample/END 和固定 baseline/coverage。
3. 高度模板使用精确 `height_stamp.gd` 模型和有界 payload，登记尺寸、实际字节 SHA256 和占用 mask；不能用脚本回调代替模板。注册表复制并冻结 payload，运行中改文件不会更新已冻结域。
4. 将资源绑定到新的 catalog。在新的 Runtime 初始化时冻结注册表、配置和实际来源 hash。已运行域不可私自替换注册表；原生恢复要求有效配置身份一致，变更后的配置须按明确迁移契约处理。
5. 对基准与新配置固定初态、seed、tick、机位和配置，读取实际 GPU 结果与原始沙/水/材料字段，核对守恒预算及允许写字段，再比较同 operation 的标准化阶段轨迹。新数值应产生可解释的字段差异。
6. 验证所有声明的水/材料选择及非法组合和数值，使用真实 Runtime 检查碰撞暂停时编辑仍能完成、消费者收敛、保存恢复、新代继续编辑和资源释放。静态产品UI按需保存在场景；G7夹具没有增加产品UI。

可运行样例为 `assets/unified_edit/extensions/extension_catalog.tres`：宽填沙、原始数学阶梯模板、宽槽搬运。`bake_extension_fixtures.py`为create-only生成器；旧核心身份记录不会随代码变化自动覆盖。

## 需要新数值能力时

现有 schema 无法表达的效果先列为未支持。扩展公共候选原语、类型化 schema、GPU ABI及公共校验/条件提交；补充对应Gate的原始字节与失败原子性回归。不得给工具添加第二个队列、提交器、权威场备份/CPU回滚、私有碰撞等待或旧后端fallback。工具名仅可在前端和旧API适配器中转换成声明，不能决定调度、提交、发布或存档工厂。

## 架构检查与允许边界

```powershell
python tools/unified_edit_pipeline/audit_architecture.py --policy tools/unified_edit_pipeline/architecture_policy.json --output test_output/unified_edit_pipeline/architecture_fresh
```

检查器从四正式场景、场景服务和扩展catalog建立保守资源引用闭包，跟踪继承、preload/路径、场景/资源绑定。当前配置的执行文件、恢复工厂、动态注册和敏感方法按已审阅身份封存；任何未审阅执行资源、方法改变、工具特例、私有写点或绑定替换都须失败并重新审阅。不要用重新生成hash来替代语义核对和相关Gate回归。

闭包包含来源清单和历史脚本中仅供取证的路径，因此它是引用上界，并不声称旧类都在执行。旧Recovery/codec仅按当前统一导入方的静态数据验证入口使用；GodotIQ为已有共享调试器autoload，列为开发工具边界。公共GPU dispatch、多阶段水响应、模拟tick、显示状态、只读表现/碰撞复制及完成后的worker回收都有明确owner和理由。`height.physics_consume`仅在is_task_completed后回收任务；执行工作槽不等待碰撞版本收敛。

九个内存违规样例覆盖私有writer、工具ID分流、legacy fallback、阻塞等待、删除worker完成检查、动态profile回调、脚本替换、变量别名隐藏record调用和资源绑定旧writer；探针不写回生产文件。检查器采用保守封存与明确语义规则，不是对任意GDScript程序的通用调用图证明。

配置扩展验收见[G7联合门](../task/sandcastle_unified_edit_pipeline/验收/G7_联合门.md)，最终功能、长稳与成本见[G8联合门](../task/sandcastle_unified_edit_pipeline/验收/G8_联合门.md)。当前字段、容量和兼容约束见[技术规格](当前技术规格.md)。

## 新增漂浮道具配置

使用精确floating_prop_profile.gd脚本的Resource和静态RigidBody3D预制体，绑定固定碰撞体、摩擦及采样云；统一服务不按类型名分流。碰撞体和点必须完全位于声明足迹半径内。当前main三件/32点/12优先块是容量边界，扩容前补ABI、所有权和性能证据。该消费者没有修改水沙的权限，不得通过Profile增加Callable、writer或私有调度。机制与复验见[漂浮道具](漂浮道具.md)。

2026-10-19道具槽选择、投放/移动和拾取统一调用FloatingPropsService.manipulate_body。只操作预存三实例，不按类型重建服务。新增交互入口必须终结旧读者并更新owner/姿态观察起点，纳入暂停、恢复失败、关闭和未知回读回归；不要在UI直接改刚体坐标或清除公共pending。道具模式独占世界左键，沙刷与道具射线分别用Terrain/Prop层。新交互代码的审计与源码身份单独审阅，历史封存保持原样。
