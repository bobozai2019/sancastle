# P02 G03 水面、浪、光学与亮纹

日期：2026-10-10。分析对象为SHA256 `761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2`的单帧`test1.rdc`。原作波速、周期、侵蚀因果和随时间的泡沫衰减不由本帧证明。

## 水面形体与可见范围

**已观察事实（C3，限本帧）：**6069/6083/6151均使用VS `ResourceId::3409`、PS `ResourceId::3410`，各返回2,145条76字节VSOut记录（65×33规则X/Z网格），每次1实例。[事件/绑定](../data/index/rdc_events.jsonl)、[原始几何](../evidence/g04_vsout.json)。VS指令17–18和42–43从16字节stride结构化缓冲`t1`取邻近数据，指令60以0.25组合高度，再由指令62–65输出位置及投影。[VS反汇编](../data/readable/rdc/test1/event_6083_vertex_disassembly.txt)。这支持缓冲驱动的变高水面，而不只是平面上的白色描边。

**可见性边界：**6069所有VSOut的Y最高6.55个场景单位，但PS指令0–2在`v4.w < 0.00001`时`discard`。按顶点`v4.w`同一阈值筛选后，6069有865/2,145条记录，Y在1.068–1.121；6083有1,671条，Y在0.806–1.121；6151有2,145条，Y在1.376–1.632。[逐事件几何和阈值统计](../evidence/p02_water_geometry.json)、[PS反汇编](../data/readable/rdc/test1/event_6083_pixel_disassembly.txt)。该顶点筛选只是光栅像素的近似，深度遮挡另可剔除；未筛选的6.55不能当成可见浪高，也不能把不同patch的Y极差直接当波幅。

**实现适配：**固定沙床样片以连续变高水面表现斜向浪前，法线须由实际水面坡度参与；可见水域/岸脚使用同一床面基准和生成态掩码。近景与掠射视角检查浪面厚度、波峰明暗、穿岸和离岸空隙。真实波速仍须带时间戳多帧观察或作为Godot验证后的替代，不宣称原作数值。

## 法线、透底、深水颜色与反射/折射

**包内事实（C3，默认配置）：**`Water`材质PathID41引用`Lit/Water` Shader PathID587及`waterNormalMap` Texture2D PathID307；默认`refractionFactor=0.0121`，`waterColor=(0.96,0.99,1.00)`、`waterScatteringColor=(0.57,0.36,0.00)`。这些是序列化默认值，不等于本帧有效常量或最终像素色。[材质typetree](../data/readable/assets/6dd7bb6bc7d926fd/41/typetree.json)、[配置索引](../data/index/visual_config.jsonl)。

**法线事实（C3，限6083）：**PS寄存器`t3=ResourceId::681`为1024² RGBA8，指令4/17/28用不同坐标多次采样，指令31–41将结果映射到方向分量、与`v2`合成并归一化。[PS反汇编](../data/readable/rdc/test1/event_6083_pixel_disassembly.txt)、[绑定索引](../data/index/bindings.jsonl)。包内`WaterNormal2D`解码mip0经上下翻转后，与该运行时纹理的4,194,304字节逐字节一致；此项资源映射为C3，限解码texel，不宣称外部payload字节相同。[逐字节复验](../evidence/p02_water_texture_match.json)。法线贴图与几何坡度均参与最终方向，不能只替换其中之一。

**光学指令事实（C3）：**同一PS绑定`t1=ResourceId::3375`（1280×720 RGBA16F场景色）、`t2=ResourceId::3386`（1280×720 D32S8深度）、`t0=ResourceId::3344`（阴影深度）。指令42–69用法线/屏幕坐标调整采样位置，读取`t2`与`t1`并重建位置；指令69–75取距离、指数衰减并调制采样色；指令99执行阴影比较，指令116输出RGB，117由`v4.w`生成饱和alpha。[PS反汇编](../data/readable/rdc/test1/event_6083_pixel_disassembly.txt)、[原始输入快照](../evidence/g04_texture_snapshots.json)。这与折射式扰动及厚度相关的吸收/散射相符，但具体物理单位、反射项和常量语义尚未全部解码，作为算法推断最多C2。

**合成事实（C3）：**三个水面事件均以`SrcAlpha/InvSrcAlpha`混合写入1280×720场景HDR，并启用`GreaterEqual`深度测试和深度写入；底面5006不混合，6196亮沫混合但不写深度。[新捕帧管线核对](../evidence/p02_water_state.json)。主帧浅水可读底形，右侧深水更蓝暗；仅视觉外观不能单独归因于alpha、吸收或曝光。[参考板](reference_board.md)。

**实现适配：**Godot水面在同一完成态读取床面/水位，建立浅水透底与深水衰减；法线结合真实坡度和细尺度方向纹理，折射取场景色/深度并做前景遮挡回退。用浅水、深水、掠射和遮挡负例逐项检查，锁定相机和曝光；不要只调一个透明度来替代所有光学层次。

## 水底亮纹

**已观察事实（C3）：**底面事件5006之后、水面事件6069之前，场景HDR展示图已出现密集亮纹；Sand材质有3D`causticsMap`引用，底面PS在`t4`执行两次三维采样，运行时`t4=ResourceId::1105`（256×256×64 R8）。[底面后展示图](board/pass_5006_sand_after_topdown.png)、[Sand PS](../data/readable/rdc/test1/event_5006_pixel_disassembly.txt)、[绑定与运行时纹理](../evidence/p02_sand_bindings.json)。包内三维`Caustics`资源与该绑定尺寸/类型吻合，但内容未匹配，资源同一性仍为C1。不能据名称或单帧断定其动态生成算法。

**实现适配：**在床面上以深度/湿域约束的细亮纹先完成可观察特征，并与水面高光分层。固定输入下分别禁用底面亮纹、水面镜面和白沫，验证亮纹确实落在可见水底、不铺满干沙，也不盖住底形；原作纹理生成法未知可采用经过单变量对照的Godot替代。

## 未解问题

| ID | 未知 | 下一查证入口 |
|---|---|---|
| Q-WATER-01 | 波高/速度、推进与退浪的时间规律 | 同机位带时间戳连续观察及少量多帧捕捉；固定seed/状态后比较 |
| Q-WATER-02 | `refractionFactor`默认值与运行时寄存器的精确对应及单位 | PS常量字节、shader反射、包内材质到运行时变体的绑定复核 |
| Q-WATER-03 | 3D`Caustics`与运行时`t4`是否同一资源、如何随时间更新 | 解码全部3D texel或查RDC资源写入链/材质绑定 |
| Q-WATER-04 | 反射与吸收的完整公式和色彩空间 | 对`t1/t2/t3`与PS寄存器做指令级跟踪，必要时固定输入单变量消融 |

这些未知不阻断可观看的固定沙床样片；不得把Godot适配公式记为原作算法。P03每次只调一个可归因因素，并保留权威水沙状态与表现时钟契约。

2026-10-10补充：[水中加沙与排水专项调查](../../../search/underwater_deposit_report.md)取得Water计算核与RDC实际字节码匹配，并确认本帧UpdateFloor保留水量字段、速度更新读取床高与有效水深。当前Godot陡坡通量响应饱和已由单变量GPU对照确认。竞品大加沙动作的时间序列、专用位移处理与全局守恒仍未知；不能用本单帧补充关闭Q-WATER-01。
