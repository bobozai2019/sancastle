# main自由挖填沙 external_v1

日期：2026-10-13。状态：已实现并完成本次功能验证。授权：用户明确要求无背包沙量、挖填互不依赖、单次最大1，并支持WASD/右键控制3D摄像机。

## 范围与版本

`main.tscn`开启`unrestricted_sand_tools=true`，两个可编辑test1场景继承此配置。它取代这些入口的库存限制；库存测试实验及未开启该配置的入口继续使用原契约。固定床面逆向实验、数值水策略、GPU回执ABI和权威字段格式沿用原版本。本次是本项目工具语义变更，没有竞品业务逆向内容。

自由编辑会真实增减域内沙体，采用现有外部源汇字段记账：

- 成功填沙：`sand_source_m3 += receipt.actual_sand_m3`。
- 成功挖沙：`sand_sink_m3 += receipt.actual_sand_m3`。
- `tool_inventory_m3`固定为0，不预填虚拟库存，不靠增大库存实现无限填沙。
- 实际挖沙仍受可挖沙层约束，不越过不可挖基底；回执保留实际量。
- 沙量闭合使用`Σ(sand+sediment)×A − initial − source + sink`。

同一domain仍64待排队/1在途；命令身份、GPU候选提交、回执匹配、一次结算、发布、脏块碰撞及两次物理帧等待沿用。自由模式的填沙不预留库存，可用量为该命令`max(0,amount×strength)+LEGACY_EPS`，仅给该请求提供有限授权。默认库存模式的可用量/预留判据不变。

## 普通保存与恢复

自由模式的`gpu_beach_edit.version=3`，`selection.sand_accounting="external_v1"`；每条GPU前缀同样记录`sand_accounting="external_v1"`。原库存模式保留header v2；现有内层字段容器/transport v1不改布局，新增显式账户标签。

v3只接受零库存账本；GPU前缀的账户标签必须与header一致。外部命令的`available_m3`必须严格等于上述有限请求授权、`stock_before=0`，拒绝虚增可用量、删除标签后伪装库存命令、未知账户模式及跨模式恢复。库存命令仍检查`available<=stock_before`，不会全局删掉该判据。普通恢复保留源码签名校验、10字段/历史完整态和构建后原子切换；旧源码签名文件不进行跨版本迁移。

## 相机与UI

main默认启用`GpuPlayerCamera`，WASD沿相机朝向移动，右键按住并滑动鼠标控制yaw/pitch；Q/E升降、Shift加速。捕获态优先读取`screen_relative`避免画面拉伸影响转向速度；松开右键、Esc、窗口失焦或摄像机失活均释放捕获。数字输入焦点阻挡移动键；右键转向不产生笔刷命令。

挖填量各自设置：0.01–1.00m³，步进0.01，默认0.10。库存标签移除，HUD不显示桶内量；节点和信号保存在main场景。参数沿场景切换复用，源汇账本随各场景独立保存。

## 本次验证及边界

- `free_tools_camera_20261013_v2/result.json`：67项通过。真实输入W/A/S/D与右键转向、捕获释放/数值焦点；从零库存连续填0.1/0.25/1.0，独立挖1.0请求；实际Physics拾取、GPU回执、沙源汇闭合；普通保存恢复10字段逐位一致、源汇精确恢复；恶意可用量/缺账户标签被拒；两个test1场景未挖先填成功，切回main保留10字段及源汇。
- `free_tools_contract_20261013/contract_probe.json`：18项原CPU/transport契约通过。
- `free_tools_inventory_regression_20261013/scheduler_admission_probe.json`：7项原库存GPU预留/不足拒绝/临界EPS/挖后结算/重复回执/int64身份测试通过。
- `free_tools_camera_20261013_v1`保留：实际功能通过，2项SpinBox默认值检查因直接比较浮点量化值误报；v2改用近似比较。`free_tools_20261013_smoke_v1.log`保留早期相机局部类型推断编译失败，已明确Vector2修复。

工具/源码身份、命令、日志及结果见`test_output/free_tools_delivery_20261013/manifest.json`。GodotIQ编辑器验证工具报`GodotIQSession has no attribute root`，未将其计为通过；上述结果来自独立实际可见Godot4.7.1 D3D12窗口及CPU headless契约检查。此次不新增性能、长稳或原作视觉复刻结论。
