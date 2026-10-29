# W07 RDC 水体贡献绘制与资源清单

日期：2026-10-07。三份原始 RDC 均只读重放；以下 ResourceId 只在对应捕帧内有效。已确认内容来自像素历史、管线状态、资源用途和绘制前后 HDR 图；算法推断单独列出。

本目录的逐绘制场景 HDR 导出图为 1280×720，中间纹理为 256×128；[WR-G0 目标板](../验收/WR-G0_参考与标准.md)的 ROI 取自另存于 `task/sandcastle_visual_reconstruction_phase2/rdc_reference/` 的 1920×1080 最终重放 PNG。不能混用像素坐标。[分辨率与绘制复核](../验收/W07_RDC分辨率与浪前绘制复核_20261007.md)记录了映射和新路线约束。

强亮绘制的 VSOut 全实例几何统计分别见 [test1](test1_foam_mesh_summary.json)、[test35](test35_foam_mesh_summary.json)、[testnew](testnew_foam_mesh_summary.json)，由[只读脚本](probe_foam_mesh_api.py)生成。三帧均为世界 X/Z 水平四边形；详情和适用边界见上述复核。

`test1` 水面 event 6069/6083/6151 的 VSOut 抽样见 [水面网格探针](test1_water_mesh_probe.json)及[W09 复核](../验收/W09_G02_test1水面网格复核_20261008.md)；event 6083 可确认 65×33 规则 X/Z 顶点及约 0.50 m 的该块高度范围。此信息用于区分水面形体与后续亮沫绘制，不直接推断原作模拟方法。

| 捕帧 | 底面/亮纹绘制 | 水面绘制 | 强亮浪前/接触绘制 | 场景 HDR |
|---|---|---|---|---|
| `test35-frame20641.rdc` | 4720/4730/4740，PS 3799 | 5442/5454，PS 3831 | **5495**，间接 DrawIndexed 6 指数 × 22035 实例，PS 3860 | 3792，1280×720 RGBA16F |
| `test1.rdc` | 4956/4980/5006，PS 3382 | 6069/6083/6151，PS 3410 | **6196**，6 × 29950，PS 3439 | 3354，1280×720 RGBA16F |
| `testnew.rdc` | 5472/5496/5554/5594，PS 3465 | 6820/6826/6866，PS 3499 | **6943**，6 × 29104，PS 3528 | 3429，1280×720 RGBA16F |

三份底面绘制均为不混合、写深度；密集水底亮纹在水面绘制前已出现。水面是 TriangleList、Indexed/Instanced（代表性 draw 的 12288 indices），SrcAlpha/InvSrcAlpha 混合并写深度，绑定场景 HDR 颜色、1280×720 深度、2048² D32 输入及相同画面的 1024² RGBA8 多色方向纹理。纹理看似法线/扰动图，但实际用途与采样公式未由绑定单独证明。水面 PS 有可解析的常量块大小，具体值/算法未解码。详情：[test35 管线](test35-frame20641_key_draws.json)、[test1 管线](test1_key_draws.json)、[testnew 管线](testnew_key_draws.json)。

强亮绘制均为 SrcAlpha/InvSrcAlpha 混合、保留场景深度、目标为上述 HDR，读取 2048² D32、结构化缓冲及 256×128 RGBA16F 中间纹理。其纹理分别由两步 compute 链产生：`test35` 3913→3918、`test1` 3867→3872、`testnew` 4154→4159；前一步读取本帧已绘制的 256×128 场景输入，后一步输出被间接绘制采样的纹理。用途和事件证据：[test35](test35-frame20641_foam_source.json)、[test1](test1_foam_source.json)、[testnew](testnew_foam_source.json)。中间纹理可见浪线与多岛轮廓：[test35](test35-frame20641_bound_1200993.png)、[test1](test1_bound_139723.png)、[testnew](testnew_bound_24305.png)。

绘制贡献可直接看到：

- `test35`：[5495 前](test35-frame20641_color_after_5483.png) → [5495 后](test35-frame20641_color_after_5495.png)，右侧主白色浪带出现。
- `test1`：[6196 前](test1_color_after_6184.png) → [6196 后](test1_color_after_6196.png)，推进浪前亮带出现。
- `testnew`：[6943 前](testnew_color_after_6931.png) → [6943 后](testnew_color_after_6943.png)，岛脚/障碍接触亮边增强。

HDR 直接导出 PNG 的显示映射可能改变整体亮度，因此还保存了 [同目标抽样像素前后值](test35-frame20641_foam_pixel_delta.json)、[test1 值](test1_foam_pixel_delta.json)、[testnew 值](testnew_foam_pixel_delta.json)。它们证明指定亮边像素在相应间接绘制后的 HDR 值变化；不拿 PNG 整图亮度差单独推断每个像素的贡献。

**边界：**可以确认水底、水面和可见强亮浪前的绘制路径与已绑定输入，不能由静态捕帧证明粒子生命周期、波速、源项公式、反射/折射算法、纹理物理语义或原作真实性能。后续 Godot 可采用验证过的适配实现；不得把目前的资源名或算法猜测当作原作事实。
