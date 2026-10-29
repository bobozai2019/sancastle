# ADR v1.40：有限复制同步候选

2026-10-11，T05默认关闭的Godot适配实验，不能称为原作算法或已确认的GPU同步修复。

依据：原split-list严格重演失败；全阶段原生复制诊断两次通过；仅commit复制及单子步详细复制仍失败。候选解释包括资源状态变化、同步及提交负载，尚无已证实根因。

`--beach-material-copy-fence` 继承同一split-list计算，不替换shader、绑定与参数，不修改源纹理。before读取七个源资源、step读取备用wetness/compaction、slope读取备用sand、commit读取当前sand，各复制1×1像素到按R32/R16/R8格式复用的三份私有纹理。不读取私有纹理到CPU，不将其发布或写入权威字段。源资源只有GPU复制读取。

当前私有纹理依照既有solver工厂为256²，逻辑容量458752字节，数量固定3，不随tick增长；实际分配/开销仍需测量。关闭在原完成态与回调等待之后释放私有RID，再释放材质计算资源。配置签名单独记录material_copy_fence。生产默认、旧参数与旧失败结果不改变。

如果候选通过严格重演，仅证明该适配配置的结果，不能确认具体缺失barrier。采用前仍需独立重复、旧冷恢复、完整负例/关闭、影响范围等价以及真实可见成本。不得用诊断PASS代替T05/G4或T06验收。

复验：`tools/run_beach_recovery_probe.ps1 -Probe beach_replay_original_probe -MaterialCopyFence`，不合并其他诊断开关。
