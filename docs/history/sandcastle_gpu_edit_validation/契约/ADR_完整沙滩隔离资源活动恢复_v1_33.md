# ADR v1.33：完整沙滩隔离资源活动恢复

2026-10-11，仅候选完整沙滩恢复。保留冻结的数值、账本、碰撞、检查点及严格逐位标准；G4不放行。

暂停且无活动事务、pending/预留时，先校验原Store封套、完整原生层及v2编辑配置/前缀。完整当前profile使用独立RefCounted资源bundle：solver的当前10字段与spare8、foam/bed双缓冲4字段、local_front、原侵蚀/材质耦合器、audit、稳定发布与碰撞shader/pipeline/buffer。已有静态场景/相机/节点不重建。该临时资源bundle是恢复数据驱动对象。

恢复API在第一次异步等待前持有私有深复制检查点，不继续消费调用者可变字典。隔离分配后实际异步读回23字段，与检查点原始字节全部比较。候选失败或提交前关闭，等待所有已提交读回回调完成，再释放候选；活动solver、generation、账本、prefix、场景发布保持。shader依赖释放顺序为uniform/pipeline先于shader，避免Godot自动失效后重复释放。

候选全部校验成功后，保持输入与tick关闭，提交新generation、原生64位prefix、高水位、账本、当前水策略/速度、浪计划及完成tick。单次render回调切换整套资源和原Texture2DRD包装，发布后释放旧资源；原碰撞节点接收新shader/pipeline和generation，清理旧epoch revision并从检查点R32床面重建64块。等待两物理帧后恢复可操作状态。视觉时钟恢复为完成tick/30，恢复后继续使用原完整耦合路径。

关闭先禁止新请求，等待恢复协调器结束；提交前关闭丢弃候选，再关闭活动分支。测试可观察实际候选提交和23读回，不用合成计数。其他尚未实现的profile历史在触碰活动状态前明确拒绝；当前原完整release profile没有结构体/rise/contact或批账本历史。

本ADR不宣称跨tick撤销/重做、旧CPU混合工具、原ULP缺陷、完整性能或长稳已完成。提交后更广泛的关闭阶段和恢复继续严格配对仍需后续验证。
