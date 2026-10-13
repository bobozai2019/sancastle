# ADR v1.18：隔离候选恢复与配置核对

2026-10-11。edit_checkpoint_lab 候选；G4 未放行。

restore需要暂停、idle、空pending/零预留。首先读盘校验并核对fixture版本、引擎、算法与控制器源码hash、SPIRV、profile/Hz、边界、策略/速度、表现tick时间和domain。numeric候选不允许erosion envelope，不能忽略其负载标志。所有不兼容在分配新候选之前拒绝，当前完成态、账本与代际不变。

等待旧回读与碰撞请求归还所有权后，使用独立新求解器初始化、复制十字段原始字节；构建失败释放新候选并保留旧分支。构建完成前保留旧texture发布和旧CPU账本。成功后提交新domain/库存/prefix/高水位与递增generation，再切换发布、复用同配置碰撞pipeline的新solver绑定、释放旧solver/history。全部64块碰撞由已读盘验证的rock/sand恢复，两physics frame后才开放输入。

revision按新generation恢复保存值，允许小于被丢弃分支的revision；切换后清空旧块revision和时间标签，不能让旧代际较高revision跳过恢复。旧回执仍因generation无效。输入ID从保存高水位继续，native ticket继续单调，不伪装旧分支身份。

仅恢复当前完成态与存活prefix，GPU快速前态和redo栈尚未由磁盘重建；跨tick/历史撤销仍需一致检查点重演。关闭时等待candidate build结束，释放尚未提交的候选，避免遗漏新分配资源；该关闭分支仍需专门运行覆盖，不能凭实现宣称通过。

当前numeric场景无TIME或累积history；独立进程严格原始字段、账本和像素已验证。完整沙滩foam/front历史、legacy混合命令及跨tick撤销/重做仍未完成，不缩小T05 G03范围。
