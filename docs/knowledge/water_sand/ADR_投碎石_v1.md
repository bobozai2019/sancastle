# 碎石显示输入约束

碎石是独立标签的显示输入，通过[DisplayIntent](../../../scripts/simulation/unified_edit/display_intent.gd)进入统一Pipeline，与编辑和水tick共享队列、工作槽、完成态及释放边界。它不冒充物理加沙命令，不写权威水沙、动量、障碍或源汇账本。

每次1–128颗，默认16；容量1024。main初始512颗，test1_geometry初始0颗。初始profile.count与当前active_count分开，只有容量足够才整批追加；不覆盖旧活动ID。固定ID／seed决定颗粒差异，GPU状态纹理为64×16 RGBA32F双槽。

[Visuals](../../../scripts/simulation/unified_edit/visuals.gd)读取公共完成态驱动贴床与随流输运，干燥或流速不足时停留。暂停不推进水平输运，编辑可按新床面投影。它不实现逐颗刚体碰撞、阻水、真实滚动或物理堆叠。

`visual_extensions.gravel_v1`记录version2、active_count及两个原始状态槽；要求`count <= active_count <= 1024`，未活动槽为零。旧格式仍受完整来源／配置和登记迁移约束，版本字段相同不代表任意旧档兼容。存档同时遵守湿痕启用时SANDUE07、关闭时SANDUE06的统一容器规则。

操作见[主场景操作](../../主场景操作.md)，显示协议和生命周期见[技术规格](../../当前技术规格.md)。
