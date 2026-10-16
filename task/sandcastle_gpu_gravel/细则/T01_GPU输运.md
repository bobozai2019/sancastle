# T01 GPU输运

负责人：主执行者。状态：[已完成]。进度：100%。依赖：T00/G0。Gate：G1。

| ID | 小目标 | 状态 | 交付物 |
|---|---|---|---|
| G01 | 固定ID状态、初始化和资源管理 | [已完成] | gpu_gravel_field.gd、initialize核、确定性seed |
| G02 | 水流输运/贴床/再湿状态更新 | [已完成] | step/reproject核、版本/去重/边界检查 |
| G03 | 已知流场与负例验证 | [已完成] | 轨迹JSONL、手算对照、G1报告 |

输入：冻结[数据与更新](../契约/数据与更新.md)、solver实际纹理定义、gpu_foam_field资源模式。不要把白沫advection参数或原作编码阈值当碎石默认参数。

实施：新增scripts/visual/gpu_gravel_field.gd和shaders/simulation/visual_gravel_init/step/reproject.glsl；每ID固定state，水深滞回与速度平滑门槛，q/h速度安全处理，位移按dt推进，移动后重采样床。一个tick的microsteps有明确总dt与上限诊断。常规运行只使用GPU输入输出；主动探针可回读位置及局部h/u验证。保持init/advance/reproject/release独立，T03再接owner生命周期。

允许修改：上述新增模块、tests/gravel/gravel_transport_probe.gd及本任务契约（变更先登记）。禁止：权威水沙核/账本、现有碰撞算法、主场景默认参数、原包与旧结果。

验收：平床恒定已知q/h时，单步和多步位移与冻结公式一致；高水无流不动、干床有残余q不动、再湿有流重新移动，方向反转正确。保持ID和count，状态有限、不越界；同seed/tick可重复，重复advance不移动；快速流microsteps不会跳过已设置的干区而无记录。

拟运行：已建立的tests/gravel/gravel_transport_probe.gd先--headless --check-only，再真实D3D12窗口。误差阈值在G0冻结（初值建议单步位置绝对误差≤1e-5m、累计≤1e-4m；限速场景单独按限速公式比较），不得事后放宽以隐藏失败。

证据：验收/G1_GPU输运.md，英文run目录中保留profile、输入场、代码/编译shader hash、每步轨迹和失败。回报按细则README统一格式。
