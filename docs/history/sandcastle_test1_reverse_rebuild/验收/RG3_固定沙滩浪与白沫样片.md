# RG3 固定沙床样片验收

日期：2026-10-10。结论：**通过固定样片门槛**；原作动态参数仍未知，实时耦合与成本留待 RG4。

## 入口与证据

- 场景：`res://scenes/sandcastle_test1_beach_fixed.tscn`；配置：`implementation/test1_beach_v8_base.json`。相机锚点、太阳、接触层、细片层及材质绑定固化在场景。初始沙体由同一权威沙高度场生成。
- [G03 manifest](../implementation/g03_manifest.json) 记录场景、脚本、shader、profile SHA256、实际 effective profile、seed 74021、generation 1、完成 tick、截图与逐帧 SHA256。运行 Godot v4.7.beta.custom_build.dff2b9bb6、D3D12 Forward+、GTX 1050。
- [60 秒视频](../implementation/test1_beach_g03_60s.mp4) 为 960×540、10 fps、601 帧，覆盖模拟 tick 0–1800；[时间戳表](../implementation/g03_video_frames/frames.csv) 逐帧记录模拟时间和墙钟时间。它证明连续视觉，不证明实时 30 Hz 成本。
- 1280×720 的主、近、掠射截图及同 tick 消融在 `../implementation/g03_capture/`；无波负例在 `../implementation/g03_capture_no_wave/`。复跑命令在 manifest。

## 观察与判定

沙体的体积、受光与阴影，深浅水中的可读沙底、底面亮纹和向岸推进的浪在主机位同时可见。定期注入波包的 60 秒序列覆盖多次入浪与退浪；近景和掠射截图显示薄浪前、细碎独立白沫及岸脚接触。目视检查未见干沙大片误白、硬白墙、重复羽片带或水面大块穿岸。画面边界和粒子尺度仍属 Godot 样片适配，不能据此宣称与原 RDC 逐像素等价。

同 tick=360 单层关闭时，独立细片改变 1,418 像素、接触层改变 5,076 像素、主水面白沫改变 27,973 像素（任意 RGB 通道差值大于 3/255）。无波条件下关闭细片改变 0 像素，接触层只改变 26 像素；有波/无波改变 273,518 像素。这支持分层贡献及无波负例。tick 540、1800 的细片贡献仅 190、135 像素，说明它是稀疏点缀，不是大范围白色遮盖。固定样片前后 rock/sand/water 权威状态 hash 保持 2750211136 / 915864041 / 2415034743。

参考捕帧只直接证明该帧的绘制与绑定；原作波速、周期、细片寿命和侵蚀因果仍为 C0。当前连续波包调度、白沫增益和接触表达是经消融检验的 Godot 适配。固定场景与 RDC 的机位、分辨率、色彩和曝光不一致，故不计算跨场景整图相似度。RG3 只验收可观看的固定沙滩，实时编辑、恢复、数值账本和性能在 G04–G05 验收。
