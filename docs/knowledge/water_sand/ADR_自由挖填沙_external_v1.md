# 自由挖填与源汇账户

两个正式入口使用`unrestricted_sand_tools=true`，自由挖填不依赖背包沙量。默认单次体积0.1m³，可调0.01–1m³；实际挖量受可挖沙层和请求授权限制，不能挖rock。

普通体积编辑使用`APPROXIMATE_EXTERNAL`：已知GPU录制请求的amount×strength进入名义源汇，包含业务拒绝，不能当作实际床沙变化的精确账户。目标高度编辑使用`EXACT_EXTERNAL`，按实际增减量结算。默认铲子`CAPPED_SHOULDERS`使用`TRANSFER_WITH_SINK`，未被两肩接收的实际挖量进入sand_sink_m3；其source为0。平滑保持守恒，压实不改变沙量。

沙存量为`Σ(sand+sediment)×cell_area`，闭合量为当前存量−初始存量−source+sink。比较前须区分名义与实际账户，不能将宏观回归阈值替代逐命令ULP授权预算。GPU候选／审计／条件提交和CPU回执验证保持独立。

源汇、配置、实际时钟和身份高水位随检查点保存恢复。原生字段与兼容性见[技术规格](../../当前技术规格.md#事务回执与账本)，实现见[checkpoint_accounting.gd](../../../scripts/simulation/unified_edit/checkpoint_accounting.gd)。
