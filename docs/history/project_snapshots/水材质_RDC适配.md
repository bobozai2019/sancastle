# 水材质 RDC 适配

日期：2026-10-11—12。用户授权直接处理当前水材质。角色：current_project_visual_implementation。依据：[竞品材质直接取证](../../competitor/水体材质_RDC详解.md)。本页描述 Godot 适配，不冒称原始 HLSL 或完整原作复刻；性能工作继续暂缓。

## 本次变化

- 水底色使用 RGB 分通道吸收，移除该路径的附加青色散射，保留已渲染底面、颗粒和阴影。吸收向量为 `(6,0.856013,0.336771)`，透射乘数为 `(0.758970,0.883854,0.968461)`；距离倍率1是当前 Godot 的选择，竞品米制仍未校准。
- 底面亮纹使用复取的256×256×64 R8体纹理，完整9级mip经Godot保存/重载后texel逐字节相同。两路流向偏移、半周期混合、时间驱动Z查询替代单张二维图平移。它是存储图案的采样动画，不是新建实时光线焦散求解器。
- 细法线读取原WaterNormal2D的B通道相位，结合本项目完成态水流进行两路RG采样和完整法线合成。空间尺度0.2、gain1、时间倍率1均作为明确的Godot参数保存。
- 表面颜色采用无2.5%固定底座的五次角度权重，太阳高光指数1500/gain1，保留已有太阳与阴影。掠射目标色选当前环境背景的线性色，避免跨场景套用竞品暖色常量造成灰紫色。
- 新style schema4增加独立材质profile/hash和严格范围校验；原schema1–3保持原范围。编译bundle、派生foam/contact的资源身份同步更新，实际参数和纹理绑定在完成态核对并进入effective_style。

权威求解器、物理shader、源汇/水沙/动量账本、E3堆挖、碰撞、场景几何与白沫规则没有修改。生成器断言原水/沙shader在新声明与fragment之前的全部代码逐字符保留。水沙原始字段及工具响应以本次回归证据为准，旧性能/严格冷恢复问题保留。

## 参数与运行资源

资源链：`rdc_style_v1.json → rdc_reflection.json → rdc_foam.json → rdc_style_base.json / rdc_base.json`；`rdc_bundle_v1.json`核对两个材质shader与固定字段索引。

| 内容 | 文件 |
|---|---|
| 明确配置 | [rdc_material_v1.json](../../../assets/water_material_natural_candidate/rdc_material_v1.json)、[style](../../../assets/water_material_natural_candidate/rdc_style_v1.json) |
| 水 / 沙底shader | [rdc_water.gdshader](../../../assets/water_material_natural_candidate/rdc_water.gdshader)、[rdc_bed.gdshader](../../../assets/water_material_natural_candidate/rdc_bed.gdshader) |
| 完整mip体纹理 | [rdc_caustic_1105_mipped.res](../../../assets/water_material_natural_candidate/rdc_caustic_1105_mipped.res)、[重载核对](../../../assets/water_material_natural_candidate/rdc_caustic_manifest.json) |
| 生成/几何不变记录 | [生成器](../../../tests/water_material_natural/build_rdc_material.py)、[索引](../../../assets/water_material_natural_candidate/rdc_generation.json) |
| 固定 / 耦合候选入口 | 固定候选场景已在2026-10-14清理中删除；[耦合入口](../../../scenes/water_material_natural_candidate/rdc_v1_coupled.tscn)保留 |

原reference_v1的shader/profile/bundle保留。修改前main及正式两入口的原字节与hash保存在[回滚索引](../../../test_output/water_material_rdc/prechange/source_index.json)。不要删除当前入口依赖的candidate目录。

## 适配选择与保留边界

1. 首轮照原PS在折射UV计算欧氏光程，出现块状透射边界；同完成态单因素证明查询路径影响。正式候选保留项目已验证的原SCREEN_UV光程与独立折射取色，参数`rdc_refracted_path=false`。原作公式仍如竞品文档记录，不因适配改写。
2. 竞品焦散局部相位来自Sand.G，本次采用已有法线B；flow来自本项目momentum/depth并限幅。原场景单位和时间未校准，不能把本项目米/秒反认作原作单位。
3. 原作掠射目标常量造成当前场景灰紫色；captured_color与sky_color、半强度分别对照，选择本场景天空色、surface_gain1。水PS原作阴影乘到Fresnel的精确因子暂未搬入；Godot太阳高光仍使用实际ATTENUATION。
4. 当前继续使用Godot线性mip过滤，原作记录是min/mag Linear、mip Point；不是像素级材质等价。几何、浪包形态、沙颗粒和其他画面层的差距不由本次材质修正全部解决。
5. 普通主场景检查点依然按配置签名校验；跨旧代码版本检查点不放宽验证。

`ImageTexture3D`用于持久化体纹理，资源保存/重载验证发生在离线导入工具，游戏启动只加载已保存资源，见[Godot API](https://docs.godotengine.org/en/stable/classes/class_imagetexture3d.html)与[资源实现](https://github.com/godotengine/godot/blob/master/scene/resources/image_texture.cpp)。

## 已完成候选验证

运行条件：Godot4.7.2 steam ed1daf0bf、GTX1050、D3D12 Forward+、1280×720、VSync关闭、曝光1、LINEAR tonemap。固定seed/tick360/generation与同一相机；检测到其他Godot进程，仅作视觉/功能验证，不作成本测量。

- [旧入口基线](../../../test_output/water_material_rdc/baseline_v1/manifest.json)和新因素候选的7个权威场逐字节相同；[因素审计](../../../test_output/water_material_rdc/factor_audit.json)记录光学、法线、3D亮纹、反射和高光的实际非零贡献，不用改变像素数作为自然感评分。
- [三机位序列](../../../test_output/water_material_rdc/sequence_v5/rdc_sequence.json)：10模拟秒，51时刻×3机位。tick360/510/660各等待30渲染帧，原始场与画面字节完全不变；实际水/底shader时钟等于完成tick/30。[动态近景](../../../test_output/water_material_rdc/sequence_v5/close_preview.webp)、[序列板](../../../test_output/water_material_rdc/sequence_v5/sequence_board.png)。不是实时吞吐、完整长稳或旧60秒Gate的重验。
- [归零审计](../../../test_output/water_material_rdc/zero_v6/zero_audit.json)：法线gain0等于关闭细法线、焦散strength0等于关闭焦散；三机位RGB完全相同。补充归零分支后的正例与已观察序列tick360均无>1bit差异。
- [前景遮挡](../../../test_output/water_material_rdc/foreground_v1/foreground_audit.json)：三机位opaque盒内部漏出均0，真实被挡表面贡献为120097/37140/57460像素，7场不变。
- [干沙](../../../test_output/water_material_rdc/dry_v1/layer_dry_audit.json)：三机位可见干沙内部9545/16758/7362个采样点，水、白沫、接触层均没有改变；不推广到所有隐藏单元。
- [schema4负例](../../../test_output/water_material_rdc/schema_v2/rdc_schema.json)：11种缺项、多项、类型、范围、hash与无mip资源错误均在模拟初始化前拒绝；日志中的11条ERROR是对应预期拒绝，不称普通无错误运行。

过程失败保留：candidate_v1折射光程的视觉块状边界；sequence_v4退出0但没有完成产物（原因未知，不计通过）；schema_v1测试器未正确本地化Windows混合斜杠路径导致提前拒绝，schema_v2修正并完整核对。原文件、旧失败和旧Gate不覆盖。

## 正式入口与功能回归

main与原正式fixed/coupled入口已切换到上述RDC材质链；静态Sun215、GPU v1.60/E3、自由相机及UI保持原配置。

- [普通保存/恢复审计](../../../test_output/water_material_rdc/ordinary_restore_v1/restore_audit.json)：暂停、保存、重新实例化恢复后的7场逐字节相同，编译配置身份不变；水/底时钟恢复为tick360/12秒，继续到tick480/16秒。普通检查点profile未篡改，不宣称旧严格冷恢复风险消除。
- [当前main功能](../../../test_output/water_material_rdc/main_smoke_v1/main_smoke.json)：12项全部通过，含真实RDC材质启用、E3配置、挖沙/填沙、原生保存/恢复、10个权威场逐字节恢复、继续和碰撞、清理。未修改这些物理或工具实现。

- [当前main UI/相机](../../../test_output/water_material_rdc/main_ui_v1/result.json)：15项全部通过；鼠标、WASD、输入焦点、UI阻断编辑与静态面板布局保持有效。
- [旧reference_v1兼容](../../../test_output/water_material_rdc/legacy_compat_v1/compatibility_audit.json)：更新共享style解析后，原profile的7场仍逐字节相同，三机位无>1bit改变，保留可运行旧材质对照。

- [正式固定入口最终捕图](../../../test_output/water_material_rdc/final_formal_v1/manifest.json)：通过原正式场景路径直接启动，同tick360三机位与已审查候选均无>1bit差异，7场与旧材质基线逐字节相同。[最终近景](../../../test_output/water_material_rdc/final_formal_v1/close.png)。
- [最终交付核对](../../../test_output/water_material_rdc/delivery_audit.json)：全部相关回归通过，RDC源hash不变；相对初始基线，原有资源仅修改style解析与main/fixed/coupled三入口。新shader/profile/资源另存，旧reference保留；62个本页/竞品页本地链接核对可用。

本次视觉交付完成，共享shader/scene/profile写窗口已释放。性能仍暂缓，旧Gate和严格冷恢复未知保持原判定。

## 2026-10-18：随完成态变化的水体侧壁

当前 main、test1 捕帧、上滩回流和原比例场景已接入静态 [WaterSides 组件](../../../scenes/components/water_boundary_sides.tscn)。这是本项目的几何/光学适配，没有新增竞品侧壁算法结论。

- 上沿顶点直接取水面边界的 XZ 和 UV；两套离线网格分别对应主场景 512×512 的半格边界与原比例 481×241 的 30×15 边界。原比例场景仍使用 32×32 状态纹理坐标，未将 RT 拉伸到可见矩形。主场景新增 4088 个三角形，原比例新增 2880 个。
- [shader 生成器](../../../tools/water_sides/build_shader.py)逐字保留当前水面 vertex 函数及所需声明/函数，另提取实际沙床的 bed_cell/bed_at；只在 vertex 末端按上下沿标记连接床面与水面。原水面/沙面 compiled bundle、shader 与钟表派生文件保持原字节。生成器 `--check` 核对输出，运行时按[来源清单](../../../assets/water_sides/geometry_manifest.json)拒绝过期派生。
- [绑定组件](../../../scripts/visual/water_boundary_sides.gd)共享正式水面已有的 rock/sand/water/local_front/async_clock 纹理对象。GPU 发布和恢复只替换这些对象持有的 RID；侧壁不读工作槽、不回读 CPU、不逐帧重建网格。固定参数随 effective profile 修订同步，源门控及显示时钟同步到侧壁。
- 下沿贴当前可见沙床，上沿包含现有水面插值、浪峰和显示偏移；干区 discard。四边采用 Godot 顺时针朝外面及背面剔除。侧面合成已经包含背景透射，输出 alpha=1，避免重复混合背景与远侧壁。
- 侧面光学复用当前水的 RGB 吸收参数，加入项目自定侧面散射和轻微扰动。光程由不透明深度、可见域出口及局部水面平面限制；局部平面是近似，未实现任意高度场射线求交、透明物体互折射或相机入水后的完整水下效果。只封场景裁切边界，内部岸线继续使用现有水沙相交。

验证入口为 [水侧壁专项](../../../tests/integration/water_sides_probe.gd)与[四场景真实菜单切换](../../../tests/integration/water_sides_switch_probe.gd)，实际结果和源码身份见[交付索引](water_sides_delivery_20261018.json)。验证覆盖边界坐标/UV逐项相同、真实近侧像素、干水负例、开关侧壁时10个权威场不变、边缘挖填、波浪、原比例涨退水、冻结时钟、保存恢复和切换。GTX1050、Vulkan Forward+、1280×720 可见窗口；本次是功能/视觉验证，不作正式成本或长稳放行。

过程记录保留：geometry_v1 测试节点名错误；v2 发现旧沙侧壁 lerp 坐标与水面顶点有微小差异；v3 修正精确顶点后功能通过，但镜头位于陆侧，对主要水侧面的观察不足；v4 的海侧纯色对照暴露三角形绕序错误，且测试误用固定采样时刻判断20秒潮位周期。最终修正朝外绕序，按实际 profile 周期采样，并增加四场景近侧界面像素检查；旧失败不覆盖。
