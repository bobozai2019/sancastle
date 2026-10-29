# ADR v1.41：失败原分支自有GPU捕获

2026-10-11，默认关闭，仅捕获本项目自有Godot，竞品RDC与既有GUI实例不操作。

`--beach-replay-capture` 在主场景与隔离回放到tick5时写入各自ready标记，暂停推进，待外部自有RenderDoc TargetControl先请求8帧捕获并写入PID匹配的go标记后继续。标记记录目标PID、分支、完成tick、Engine process_frame；帧号差不换算秒数。门超时75秒返回失败，不继续冒称捕获成功。配置签名包含此诊断开关。

助手通过ExecuteAndInject启动唯一自有Godot，记录实际参数、目标PID与16份RDC大小/hash；正常断连并取得最终严格报告才判定捕获协议成功。协议成功与严格重演通过分开：失败运行的捕获仍可成功。所有脚本与产物采用完整英文路径。

单帧只能证明该帧事件/资源/绑定。pipeline reflection的native rawBytes、实际ConstantBlock指向的buffer字节和存储图像descriptor分别保留，不把unknown解码的零当成真实常量。ResourceId仅在对应捕获内使用；跨捕获使用有证据的dispatch签名、顺序、格式与资源别名图对齐，不能直接比较ResourceId数值。

模拟序列比较明确排除并保留渲染dest_buffer、碰撞packed_heights与CFL时序事件。被排除事件不属于已证实逐项相同的范围。sand导出是SetFrameEvent(event, True)后的重放派生字节，不是运行时该pass输入的原始快照；禁止据此声称默认首差异或全部输入相同。

复验：tools/run_renderdoc_replay_capture.ps1；原生绑定取数复用tools/renderdoc_binding_probe.py的唯一PID上下文；比较tools/compare_owned_replay_bindings.py。后续捕获窗口需要独立记录，不通过已有早期窗口代替编辑前后验证。

窗口参数：`-CaptureTick 14 -CaptureFrames 16`在两笔编辑的execution_tick15/16之前等待；`-CaptureFrames 8`仅改变外部请求的窗口长度。CaptureTick合法范围1–14（缺省5），每个分支CaptureFrames合法范围8–24（缺省8），预期RDC数量为2×CaptureFrames。ready保存实际tick，配置签名保存capture_tick，go和host结果保留实际请求帧数。必须以RDC事件确认编辑pass是否真的进入窗口，不用门控时点或请求数代替覆盖证据。
