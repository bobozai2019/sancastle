# test1 浅水通道与项目水槽适配

## CHANNEL-TEST1-01：参考帧与地形来源

- 更新：2026-10-23；范围只含沙面地形与该帧可见浅水通道。
- 来源：`D:/godot/project/sandcastle/rdc/test1.rdc`，225224034 字节，SHA256 `761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2`。与既有几何来源相同，读取前后身份一致。
- 分类：观察事实，C3。本次用 RenderDoc 1.46 直接重放 E5006，导出 VS t0 `ResourceId::139571` offset 0、length 8388608，并读取捕帧自带缩略图。原始缓冲和派生图分开保存在[证据目录](evidence/test1_channels_20261023/manifest.json)，没有依赖临时测试目录。
- 缩略图显示沙堆间及岸边有曲折的浅水通道。这里只描述本帧外观，不能从图推断沟槽生成算法、潮汐周期或水流方向。
- 按[已有高度解码公式](test1场景尺寸与沙深度.md#geom-test1-02完整沙面高度可解码)复算后，与正式保存的 `source_sand_1024x512.f32` 最大绝对高度差为 `1.1920929e-6`，见[复算记录](evidence/test1_channels_20261023/height_comparison.json)。新原始缓冲 hash 与旧导出不同，不能宣称逐字节相等；这次保留原基础高度，不用微小重放差异改写旧数据或旧报告。
- 复验：核对 capture 和 manifest 内各文件 hash；运行 `qrenderdoc.exe --python D:/godot/project/sandcastle/docs/competitor/tools/export_test1_channels.py` 前将脚本 OUT 改为新的英文证据目录，避免覆盖原结果。用 uint4 高度公式解码新缓冲，与正式保存的 float32 基础高度比较。
- 未知：缩略图不是独立时间序列；原作真实沟槽形成方式及更新规律未确认。本次未重新确认全部 patch、材质公式、速度或侵蚀因果。

## CHANNEL-GODOT-01：原比例沙滩的水槽造型

- 分类：Godot 适配；参数来自本项目设计，不给原作算法评级。
- `assets/test1_geometry/channels.json` 定义三条入海弯槽与一条支流；Catmull–Rom 中心线按段采样，在中心槽底与原床面之间使用 smoothstep 岸坡。重叠槽取最低床面，只在可见域降低初始沙厚。
- 槽底 Y=0.62–0.82 m，中心半宽0.32–0.62 m，岸坡过渡宽0.55–0.72 m。0.95 m 初始静水位使内陆槽底保留约0.13–0.33 m浅水。原有沙塔峰值、30×15边界、Y=0基底和20模拟秒边界周期保留。
- 生成器 `tools/test1_geometry/build_channel_state.py` 从正式基础高度重新生成 `initial_state.f32`；`bake_channel_seed.gd` 把它固化到统一表现 seed。直接启动与验证入口消费同一份 seed，运行时不额外挖槽或建立第二套水面。
- 初始水沙库存随新地形重新建立，槽口之后的涨水、回落、编辑及碰撞使用现有统一流程。此次初态改动不是运行时沙源汇，也不保证旧来源签名的检查点可直接恢复。
- 适用边界：这是参考画面启发的岸形设计；未把新增水槽的位置、宽深或中心线声称为原作精确几何。
