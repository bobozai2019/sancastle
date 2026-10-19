# C07 UI自由摆放与拾取

更新：2026-10-19。角色：contract。范围：main既有水瓶/木板/木棍，各1件。根据用户本轮要求扩展原阶段的固定布局操作，原G1–G6契约/证据按原来源保存；不增加刚体数量、Probe/Height ABI或原生权威字段。

## 场景与API

面板、三个槽位、拾取/取消按钮、提示和落点光圈预存为场景。选择槽位进入摆放模式，左键目标位置投放或移动既有实例；拾取关闭目标实例可见性/碰撞/受力采样并显示为槽位中。没有动态节点/实例工厂。返回沙刷、Esc、右键或选择沙滩工具退出道具模式；输入不得同时启动沙刷。

服务API：manipulate_body(body_id:int, point:Vector2, yaw_rad:float=0, pickup:bool=false) → 异步Dictionary。

| 字段 | 约束 |
|---|---|
| body_id | 已登记的正整数ID；UI固定1/2/3，服务不按种类分支 |
| point | 放置时有限XZ；离权威域边缘至少footprint_radius_m+0.2m |
| yaw_rad | 有限；UI按15度步进，作用于预存初始basis |
| pickup | true只收回在场实例；重复拾取拒绝 |
| 返回 | operation_id/error/domain_id/generation，已接纳操作恰有一次终结 |

错误包括invalid_body、invalid_position、out_of_domain、occupied、already_picked_up、busy、transition_busy（UI）、closing、stale_generation、identity_exhausted和既有采样/后端错误。拒绝不改变物体位置或库存状态。放置时邻体XZ安全间距为双方足迹半径之和+0.05m，先检查再在保持边界重新检查。

## 读者、物理和时间

先设置interaction保持并停止新探针，跨真实物理边界终结已准入步，再等已注册探针的真实回调。未知读取沿公共维护重试，不清pending强行过关。随后换owner_token并丢弃旧姿态历史。关闭优先停止准入并终结操作，旧代或关闭后不能继续移动物体。

三件始终登记；world_registry仅包含在场实例。拾取物体freeze、隐藏、layer/mask=0，不参加受力/接触恢复/探针。全部拾取后不请求空探针，局部观察起点随水完成时间更新，水编辑生产继续。重新投放恢复layer/mask=2/3、零线/角速度、非睡眠，按目标水床和实际shape下沿确定安全初始高度；其他物体保留之前速度和睡眠。

每次操作结束建立新的消费者观察起点：origin_time_s=当前完成水时间−admitted_time_s，不补偿手动保持期间时间。投放目标actual_time清零，body_time_origins记录其共同积分起点；在场实例以actual_time+body_time_origins对账admitted_time_s。水沙时间/字段/账本不变，正常物理步仍来自Jolt及公共完成态预算。

## 生命周期与兼容

user暂停可操作；save/restore/boot/close期间UI拒绝新交互。交互与生命周期busy串行。失败恢复保留原摆放/槽位状态，成功恢复与重进使用原authored layout复位全部三件。UI选择、手动位置、库存状态不写检查点。

来源catalog schema3/id=floating_props_consumer_v3保留原已登记source_configuration，并额外登记本轮修改前正式检查点的完整配置及SHA256。声明参数相同，完整目标source map精确匹配后才能投影；全native3字节、账本和实际时钟保留。additional_sources最多4，未知来源不学习、不自动信任；离线构建器仅允许七项明确UI/消费者文件变化，其他权威来源必须逐字节相同。

API和边界以实际代码及本次验收来源为准。验收结果单列[UI报告](../验收/UI_摆放与拾取_20261019.md)，不写入历史Gate或用旧成本判定新负载。
