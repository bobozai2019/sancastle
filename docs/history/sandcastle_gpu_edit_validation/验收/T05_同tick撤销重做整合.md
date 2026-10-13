# T05 同 tick 撤销与重做整合

2026-10-11。原生候选层，不放行G4或正式性能。

`tests/edit_validation/run_scene_probe.ps1 -Undo -FastFullWet`：061711_scenes 13项通过，包含新增实际物理射线、实际引擎输入后的撤销；061819_scenes 16项通过，新增B/C/E重做。各目录包含manifest、权威及发布字段bin、日志和artifact_index，源与产物均可追溯。硬件GTX1050，Godot4.7.2，D3D12 Forward+，可见960×540窗口。

三笔B/C/E同tick编辑后，连续undo逐位等于每个对应前态：十权威字段与两发布纹理、原double库存、已应用日志长度和执行prefix长度。每次generation递增、revision单调，高水位不倒退；64块碰撞shape与GPU相同，25点实际PhysicsRay误差≤0.865μm。旧generation回执无效。随后redo的三笔规范化新事务逐位复现每个原编辑完成态与库存。

GPU拒绝命令释放pending前态、保留真实rejected prefix；在此前缀上新编辑再撤销正确。撤销后实际鼠标事件采用物理窗口坐标注入，PhysicsRay拾取、native新ID及代际正确，随后undo逐位恢复。待排命令阻止undo且保留名义预留；暂停20帧及显式advance尝试后字段/tick不动；运行态要求暂停，跨tick要求检查点重演且所有字段不变。

061559_scenes 首轮测试GDScript类型推断失败，原日志/hash保留；补显式bool后编译检查和061609首次12项运行通过。后续13/16项扩展不覆盖旧失败。运行过程没有为undo发起CPU全图读回；测试的边界全字段bin是验真，不作为热路径收益证据。

未完成项：跨tick checkpoint replay、重做跨tick分支、保存pending边界、版本化sidecar、全字段与视觉history严格恢复/继续配对、旧smooth/compact混合恢复、恢复中失败/退出覆盖、真实成本。T05 G03仍进行中，C首笔100ms反馈失败未变。

061851_scenes：默认慢路径（未启用fast_full_wet）17项回归通过，新增单格临界EPS借差使库存为负、undo精确归零、redo精确恢复同一负库存；原权威及发布字段逐位恢复。

062001_scenes：UI ID生成改为兼顾高水位后，65笔快速队列/容量拒绝/忙时输入/64块碰撞一致性回归通过；未改变原有队列容量或预留语义。
