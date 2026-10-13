# ADR v1.25：完整沙滩 GPU 事务入口

2026-10-11。API候选原语，T05仍进行中，G4未放行。

新增静态继承场景edit_beach_gpu_lab，保留完整原沙滩profile、sediment/material侵蚀、foam/front、80浪计划及业务节点。仅替换solver为原生GPU水沙编辑候选、碰撞代理为已验证的事务保护候选。原默认入口不切换。

完整场景直接API只消费当前tick且空队列的合法命令。活动tick、shadow/prefetch/checkpoint或已有GPU事务时拒绝新单笔API。事务读取原shadow_domain库存；匹配128byte真实回执结算实际量，成功才记录applied；同generation/revision授权发布，脏chunk及八邻块完成后等待两physics frame。物理步进与新API不能穿过事务。B/C/D/E策略均复用原shader，不更改数值规则。

沙/水使用既有候选发布纹理；新增两张R32稳定动量纹理，在受授权完整发布时复制qx/qz。避免回执尚未结算时，完整沙滩着色从正在提交的物理动量槽取新值。该每tick发布复制的成本尚未验收。

显式shutdown先停止新输入和步进，等已经开始的事务实际结算/发布/碰撞以及原tick/shadow/checkpoint工作完成，之后关闭碰撞epoch、等待实际staging回调归还，才释放coupler、视觉history、稳定发布纹理和solver。没有中途撤回已结算库存。

CPU工具输入尚未改成GPU调度，API候选不能冒称真实UI整合。当前gpu_prefix记录实际输入/结果/策略/库存，但未序列化进完整检查点，因此GPU操作后的保存明确返回gpu_beach_prefix_not_serialized；不生成缺失prefix的假完整文件。完整场景undo/redo、磁盘恢复、排队UI和退出广泛覆盖仍待完成。
