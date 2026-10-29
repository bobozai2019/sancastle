# 独立近似 GPU 编辑实验

入口现位于 `res://scenes/approx_gpu_edit.tscn`，运行脚本和资源已迁出 `tests/`。本目录保留复验探针；旧验收记录中的路径与 hash 是迁移前证据。在 Godot 编辑器打开该场景按 F6，或运行：

```powershell
& 'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --path 'D:\godot\project\sandcastle' --rendering-driver d3d12 'res://scenes/approx_gpu_edit.tscn'
```

首次没有导入缓存时，先用同一引擎执行 `--headless --path <project> --editor --import --quit`。`project.godot` 的默认入口仍是生产 main。

选择挖/填工具后左键点击或拖动；挖/填量可分别调整。空格或按钮暂停，暂停仍可编辑。相机固定；红/蓝圆环放在 0m 参考平面，其XZ与GPU消费位置一致，沙丘上会有透视偏差。库存是请求量的估算值，无沙可挖、限高或截边均可能不同于真实体积。复位排空已有提交后重新加载固定初态；关闭先停止准入再排空。实验不支持正式存档、撤销或恢复。

水模式：仅沙编辑、水量模板、水量与速度模板。默认完整视觉、80浪调度和侵蚀保留；水模板有非守恒变化，不能用于要求精确库存、物理碰撞或检查点的生产玩法。

`res://assets/approx_gpu_edit/trial_profile.tres` 固定半径0.3m、平面0m、默认每笔0.015m³、water mode2。诊断开关和准确GPU中间对照只在这个独立资源中消费；不改变生产配置。准确中间对照保留GPU算法，不代表完整准确库存事务；GPU内部状态需要窗口末诊断，不逐笔读取。

复验脚本（全部串行）：

```powershell
python tools/approx_gpu_edit_trial/run_probe.py --water-mode=2 --diagnostic
python tools/approx_gpu_edit_trial/run_probe.py --probe=geometry --water-mode=2
python tools/approx_gpu_edit_trial/run_probe.py --probe=lifecycle
python tools/approx_gpu_edit_trial/run_probe.py --exact --diagnostic --exact-policy=3
python tools/approx_gpu_edit_trial/run_probe.py --exact --diagnostic --exact-policy=0
python tools/approx_gpu_edit_trial/run_pairs.py live
python tools/approx_gpu_edit_trial/run_pairs.py frozen
python tools/approx_gpu_edit_trial/run_cost.py --seconds=300 --live
python tools/approx_gpu_edit_trial/analyze_runs.py
python tools/approx_gpu_edit_trial/check_protection.py
```

成本探针屏蔽外部输入，生成4Hz的固定交替堆挖轨迹，保存每笔真实请求时间、tick、准入、发布请求、绘制事件、计时和原始快照。每个run使用新英文ID，不覆盖旧失败。VSync开启；30s窗口、GPU诊断与长观察分开。CPU frame_post_draw不是GPU完成或scanout，不能当作逐像素反馈。准确核逐pass诊断批量限制为1以避免时间戳上限；正常运行批量最多8、pending64。

权威结果与局限见[任务验收](../../../task/sandcastle_approx_gpu_edit_trial/验收/README.md)，原始数据见 `test_output/approx_gpu_edit_trial/`。
