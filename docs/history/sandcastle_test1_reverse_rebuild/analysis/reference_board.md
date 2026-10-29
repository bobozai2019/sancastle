# test1 固定参考板与画面分层

日期：2026-10-10。基准捕帧SHA256：`761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2`。本板只描述该帧可见状态；没有时间戳序列，不能从此推断推进速度或白沫寿命。

## 比较口径

- 主画面为Present事件6645的`ResourceId::427`，1920×1080、`R8G8B8A8_UNORM`；[`主画面PNG`](../data/readable/rdc/test1/event_6645_present_427.png)从同一资源原始字节无校色转换。来源、hash与命令在[`p02_present_preview.json`](../evidence/p02_present_preview.json)。另一个交换链buffer `ResourceId::428`不是本帧Present参数。
- 原始场景HDR `ResourceId::3354` 为1280×720、`R16G16B16A16_FLOAT`。[5006底面后](board/pass_5006_sand_after.png)、[6083部分水面后](board/pass_6083_water_after.png)、[6184白沫前](board/pass_6184_foam_before.png)、[6196白沫后](board/pass_6196_foam_after.png)由RenderDoc同一`SaveTexture`设置导出。其PNG展示映射未指定曝光，不能与最终RGBA8逐像素比颜色。[导出参数](../evidence/p02_pass_previews.json)。
- HDR预览在显示上相对最终画面上下倒置；[`面向观看的白沫后图`](board/pass_6196_foam_after_topdown.png)仅翻转原PNG，原图和原始HDR字节保留。[变换记录](../evidence/p02_oriented_pass_previews.json)。最终画面坐标采用左上为原点的 `[x0,y0,x1,y1]`，右/下端不含。
- 植被、玩具和UI只影响遮挡与构图。视觉评价遮罩其区域，不把它们纳入本包实现目标。Godot对照须另记机位、FOV、实际viewport、曝光、profile、seed、tick及完整完成态；目前只固定竞品主帧，尚未建立可比Godot镜头。

## 主画面局部目标

ROI均来自上述最终呈现的同一帧，裁图脚本和hash在[`board/manifest.json`](board/manifest.json)。

| 层/ROI | 坐标 | 这一帧可观察的目标 | 边界 |
|---|---|---|---|
| [干沙与高沙体](board/dry_sand_and_volume.png) | `[350,100,1010,790]` | 连续暖沙底、显著高度与受光侧面，阴影能读出体积 | 沙塔形成机制不由静帧证明；已有预置物须排除独立模型的可能 |
| [浅水与沙底](board/shallow_water_and_bed.png) | `[690,400,1110,840]` | 浅青水下仍能跟踪沙底沟脊和高低，水色随厚度变化 | 不能把最终色差直接归因于单一alpha参数 |
| [深水](board/deep_water.png) | `[1400,350,1820,820]` | 右侧颜色更深，底部细节减弱但仍有局部地物与光影 | 与浅水需在同曝光、同输出变换下对照 |
| [主推进浪](board/advancing_wave.png) | `[1020,130,1380,960]` | 右侧斜向浪前有弯曲边界、抬起的水面和碎白亮芯 | 单帧不证明运动方向、周期或寿命；方向需带时间证据 |
| [水沙接触](board/sand_water_contact.png) | `[640,390,940,690]` | 左中沙脚与薄水相接，水下底形、湿边和局部碎亮能区分 | 白边不能永久覆盖干沙；Godot需同床面基准负例 |
| [障碍脚](board/obstacle_foot.png) | `[1070,135,1380,430]` | 上部高沙体/岩脚附近浪线绕形，遮挡关系清楚 | 装饰物自身不纳入复刻，但须测遮挡与近景贴合 |

## 分层与辅助视角

[`pass_graph.json`](pass_graph.json)记录本帧事件及资源链：底面/亮纹先写场景HDR，水面随后写同一HDR，6196再绘制独立亮沫，后处理和UI将场景内容接到Present输出。底面已可见密集亮纹；水面与独立亮沫并非同一绘制。主帧里的所有亮白不能一概归给6196。

P03固定样片的辅助镜头需要近景和掠射视角：近景暴露沙体厚度、岸脚缝和白片尺寸；掠射暴露水面起伏、反射与几何穿岸。竞品捕帧只固定主视角，辅助视角是Godot验收机位，不冒充原作第二镜头。

世界尺度、竞品相机矩阵及原作物理波速尚未复原。旧验收板的尺度/容差可作为Godot既有候选测试入口，但本板不把旧结果累计为本任务完成。
