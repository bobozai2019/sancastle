# ADR v1.43：后端与API验证归因

2026-10-11，仅ULP疑点诊断。MVP与正式性能仍冻结GTX1050/D3D12/1080p/VSync off，不改总纲范围，不用Vulkan通过替代D3D12验收。

run_beach_recovery_probe.ps1增加RenderingDriver（缺省d3d12）与GpuValidation（缺省关闭）。原profile、seed、命令、shader与数值公式不改；owner保存实际启动参数，日志保存实际后端。验证请求进入configuration_signature.gpu_validation_requested，不把“请求”冒称已覆盖所有GPU错误。

Vulkan/D3D12交错，以及D3D12验证请求/无请求交错，分别作为单因素线索。所有输入源码须在各组终态核查hash；每个独立目录保留结果，失败不覆盖。变化的是后端或API验证环境，可能同时影响编译、驱动行为、同步和调度，不据样本直接确认根因。两次诊断通过不等于全任务放行。

源码取证限定官方Godot、运行二进制报告的ed1daf0bf提交；完整commit与tree SHA分开记录。下载路径、大小、hash、MIT许可原文保留。源码语义不自动证明本机所有debug输出均进入Godot日志。

匹配源码的compute_list_add_barrier实现保存状态、结束列表、重新开始并恢复pipeline/uniform绑定。因此此前内部barrier实验不能当作已经直接插入某个D3D12 UAV硬件屏障的证据；仍须核对图依赖及实际提交。D3D12 context验证分支调用EnableDebugLayer，不能据此宣称开启了GPU-based shader验证。

复验用同一Probe依次RenderingDriver vulkan/d3d12/vulkan；D3D12另独立切换GpuValidation。正式默认与保存恢复数值门槛不变，G4仍待D3D12完整证据。
