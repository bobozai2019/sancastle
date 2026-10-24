# 活跃数值源码有界只读审查

结论级别：C0（根因未知）。在下列8份实际活跃核心文件中，没有找到能直接确认、且足以解释当前同源A/A重放差异的未初始化读、并发读写或状态污染。这里的“未找到”不是并发安全证明，不代表数值门通过。本审查未启动GPU、未修改运行代码、容差或权威算法，未读取更多核心实现以展开物理修复。

## 本次证据边界

事实来源为同目录 `analysis.json` 及 `main/start.sandue`。该run原始Codec.load路径下 end-only 与 with-middle 的A/A、A/B均严格失败。with-middle已保存边界 restored、place_sand_0、place_sand_1精确一致，place_sand_30首次观察到差异；这仅定位到fill后第2至30tick之间，尚未识别首个实际分歧tick/dispatch。AA在此sand仅2个分量不同，max 5.960464477539063e-8。中间capture不能消除本次失败，也不是修复。此前memory取值probe成功不再用于推断本run根因。

1003项检查中的64项失败均为比较类，准入、finish、end_requested空和每次completed_tick恰好+1无失败，source_drift为空。native.control只有u32 word2为恢复generation（1002/1003/1004）的身份差异，不能把它单独列为物理错误；其他元数据一致。此审查不将control整体相等检查的预期身份失败扩充为权威字段问题。

从start配置读得：solver_id=muscl_mc_ssprk2_v1，enable_erosion=true、prescribed_tide_boundary=true、main boundary mode0（mean0.10/amplitude0.11/omega0.35/phase0/period16），enable_structures=false、ordinary_cohesion_yield_height_m=0。故一阶旧水录制分支和geometry mode3 overflow分支不是本run活跃物理路径。

## 有界源码观察

| 路径及行号 | 可直接确认的事实 | 对根因的限制 |
|---|---|---|
| `scripts/simulation/unified_edit/water.gd:85–99,117–156,159–162` | 初始化包含MUSCL选择、实际boundary绑定；波包上传有界，boundary push在实际录制时构建；通用dispatch逐compute-list记录。 | 没有据此证明引擎如何生成资源屏障；不能凭缺少显式barrier认定错误。 |
| `scripts/simulation/unified_edit/water_muscl.gd:49–97` | 缓存键含dt/cell size/boundary/wave retention/coupled callable/prescribed boundary；64候选步固定按edge、decide、drain、euler、finalize、coupled、normalize排列，boundary为动态callback。 | 未见以generation作物理系数或随机tie-break；缓存键缺项导致实际push陈旧并未证实。 |
| 同文件`:100–104,127–164` | 私有图像创建未给初始内容；trial/safety/audit/indirect buffers以resize后的零数组创建。phase输入/输出u1/u2为不同RID；finalize到槽1，normalize由槽1到槽0。 | 私有图像初始未填零本身不是未初始化读证据：必须进一步证明某活跃consumer先于producer消费，这在本有界检查未证实。未全面审阅所有RK核与include。 |
| 同文件`:167–188` | 每条描述单独begin/bind/dispatch/end；标准coupled固定描述被内联，boundary保持实际callback。 | 自动屏障行为需匹配Godot引擎实现或GPU证据。本审查没有相应源码证明，既不声称自动屏障充分，也不声称缺失。 |
| `scripts/simulation/unified_edit/coupled.gd:26–41,49–64,72–85,90–109` | MUSCL使用exchange核，sediment读live、sand读spare，输出sand live和私有exchange；再copy sediment。material与slope用分槽及独立staged缓冲，随后consume/commit；accepted indirect调度，固定阶段顺序。 | 未观察到exchange的同一输入输出RID别名。support/slope缓冲的完整producer写覆盖未在8文件范围内证明，不能把其可能性写成既定缺陷。 |
| `shaders/simulation/erosion/sediment_exchange.glsl:21–44` | 每格读取同格输入，计算交换，写同格sand和sediment输出；dirty使用整数imageAtomicMax。输入/输出按当前coupled绑定分离。 | 没有浮点atomic决定沙分布；dirty integer atomic不能解释为已证实的物理非确定性。 |
| `shaders/simulation/muscl/rk_decide.glsl:27–44,50–55,65–99` | 工作组统一进入速度归约，shared sx/sz每lane先写后barrier；mode0重置decision/trial与相关暂存、mode1重置本次阶段统计；lane0进行CFL/接受与dt更新。 | stats低位累计统计未逐tick清零并不自动构成污染；本文件未见其被用作物理dt或field输入。atomic统计函数本体未展开，不能由函数名猜测。 |
| `shaders/simulation/muscl/rk_euler.glsl:10–36` | 每个像素调用state_at，初始化四向flux和边界压力，读取edge/drain/correction/bed_source后写stage_out自身格。非有限值设置错误；按boundary清除海侧动量。 | state_at/face/cap_state等include未纳入本轮深审，无法对整核读覆盖作完整证明。当前文本没有直接可确认的跨格输出读写冲突。 |
| `scripts/simulation/unified_edit/boundary.gd:19–21,88–95` | main用mode0；恢复取配置、requests、start_times并仅将wave.generation重绑新代。 | 新代用于请求身份，不是此处物理幅度/随机种子。不能由身份换代推出数值变化。 |
| `scripts/simulation/unified_edit/boundary.glsl:21–39,73–83,105–113` | 一个64线程工作组，lane以z=lane+64k分担不同边界格；main overflow=false；source/sink先写shared再固定归约；time读control[8]。 | 活跃mode0内没有线程写另一lane同一格的直接冲突；geometry overflow的并发条件不适用于main。未见control generation word2进入物理数学。 |

## 停止点

不扩大epsilon，不以账本一致替代逐点字段精度，不以capture成功记录覆盖失败。不再深挖整个求解器或尝试修复；当前仅可报告原始A/A非确定性/不一致已复现、首次保存分歧窗口已缩至fill后第2–30tick、具体根因C0。若后续另行授权继续，应获取最早分歧tick/dispatch的同源输入输出与匹配引擎资源依赖证据，再区分应用状态、算法读写和后端行为；这不是本轮已完成工作。

## 8文件身份

以下hash均直接核对start.checkpoint.configuration.sources，true表示当前磁盘字节匹配本run冻结来源。

| 文件 | matches checkpoint sources | SHA256 |
|---|---|---|
| `scripts/simulation/unified_edit/water.gd` | true | `8b6d8093f3e2518eda1b41f790a2e1affb202f193ffae7b38dd3670faa2a2a6a` |
| `scripts/simulation/unified_edit/water_muscl.gd` | true | `383b8d1c8371e607ee935580c1b8edc872cf1164cb7e347a962a3f9432fa257d` |
| `scripts/simulation/unified_edit/coupled.gd` | true | `b80c7b7aca3fb5b351811390f9ed9ecc6c9e2c715518496ba09f6f346001ff62` |
| `scripts/simulation/unified_edit/boundary.gd` | true | `20a62b9c4b580868b261103fe034e7e61646a8fb40de61a555c6ee546861bcf1` |
| `scripts/simulation/unified_edit/boundary.glsl` | true | `8949333ac4ca60f02c07ba1bb39346657bc5cce0d60b078c8f7135bfc6c089ea` |
| `shaders/simulation/muscl/rk_decide.glsl` | true | `6d51c59ed047d333f8855016d00b2a6cc464f4cb00c8b854c42ed96811bbd3f7` |
| `shaders/simulation/muscl/rk_euler.glsl` | true | `daf72a12c24352106a2b9e6aa8fbc1a935b5d13b380e2090042c344b553b2d06` |
| `shaders/simulation/erosion/sediment_exchange.glsl` | true | `da563ac4f8273e16ec95a58deb15eb443bfcc386d656037bb0436fd879d82a02` |
