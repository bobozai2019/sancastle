# ADR v1.29：完整快照失败隔离与选择状态

2026-10-11。完整候选，G4尚未放行。

完整native快照汇齐后，写文件前先验证主/备用物理字段及双泡沫/床面历史、water/q/foam旧投影；不只在读文件时验证。原生派生数据含NaN等非法值时不写checksummed坏文件。请求失败或验证失败，先等待全部实际已提交回调归还，再清理capture/pending_save标志。保留原物理/视觉字段、库存与prefix，停止ready、playing、admission和显式tick，允许安全shutdown；不自动把失败后端重新开放。

测试专用子类通过原请求函数的Error返回钩子注入第27次请求失败，26次其余请求仍真实执行；另在真实raw_sand回调的派生bytes副本中注入NaN，不修改GPU物理纹理。仅预期的两个错误抑制push_error以便负例验收，其他错误沿用真实_fail。不能冒称驱动故障或全局GPU状态已被损坏。

gpu_beach_edit sidecar升级v2，增加当前水策略和signed speed选择态，并验证有限值/范围；prefix内逐笔配置仍独立保存。冷恢复还原当前选择，不把最后执行命令的配置或默认C策略冒充当前选择。旧v1证据原样保留，候选没有默认迁移；SANDCP01外层仍v1。

新v2文件的checkpoint完成态配对通过，但默认七tick继续再次出现原四格沙ULP失败。保存失败/关闭可通过独立边界验收，完整恢复门仍未通过。
