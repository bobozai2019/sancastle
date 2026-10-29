# test41 / test42：GPU 堆沙与水编辑补充调查（v2）

日期：2026-10-11，接续 2026-10-10 调查。v2 明确将单帧无法证明的画面因果贡献保持为 C0；初版原文与全部原始数据保留。范围为 GPU 沙、水及相关粒子效果，不涉及竞品业务方法。本报告补充[此前十帧调查](edit_performance_report.md)：**test41 找到实际 GPU 编辑片段，包括沙高度笔刷和两次专用水笔刷；test42 没有匹配到这些调用。**此前“实际调用未知”的边界因新证据缩小，原作动作耗时与 CPU 同步调度仍未知。

## 原始身份与比较边界

| 源文件 | 字节数 | SHA256 | 捕获帧号 |
|---|---:|---|---:|
| sandcastlegame/test41.rdc | 256177273 | f1794a7235a79f7a73bd6f4085bef7ecbb3a7dc39ce8a8a7aac955ee5beb3c0d | 7756 |
| sandcastlegame/test42.rdc | 253642768 | b5d06ec208a49518c98277fe68efce55a9d18728aadf4551720c0018702fbdef | 7590 |

RenderDoc 1.46，两文件前后 hash 相同。调用名称为 D3D12。文件名不能代表时间顺序；帧号没有时间戳，不能把 test42 当作 test41 编辑后的状态，也不能由帧号差换算响应时间。源码包仍是已核对 hash 的 sharedassets0.assets。

## test41 的实际链路：C3

| 顺序 | 事件 | 已匹配的 GPU 操作 |
|---|---|---|
| 常规模拟 | E700 / E706 | Ground 速度/高度积分 |
| 常规水更新 | E712–E771 | 更新床面，三组水速度/高度/平流子步，更新 amount/tangent |
| 上传笔刷参数 | E855 | CopyBufferRegion：CPU 写过的 ResourceId::336 → 32 字节 ResourceId::30348 |
| 沙床编辑 | E863 | Ground.Paint，根据印章纹理、变换与参数修改 ResourceId::30347 |
| 沙面辅助状态 | E869 | Ground.UpdateTangent |
| 水编辑一 | E878 | Water.Paint，实际 mode=2，36 字节参数缓冲区 |
| 粒子编辑 | E886–E1200 | Kill 与多轮 Compact/Swap 等 GPU 粒子核 |
| 水编辑二 | E1210 | Water.Paint，实际 mode=6，36 字节参数缓冲区 |
| 辅助采样 | E1225 | Readback.Update，256×128 stride32，共 1 MiB |
| 绘制 | 见 ground 使用表 | 同一 GPU ground buffer 随后供 VS 读取 |

Ground.Paint 字节码 SHA256 `d37af2736147fd90f62ecbf8230bb0162a961ba2b16bce44a29d02fb2cdb30aa` 与包内 :640 变体精确匹配；Water.Paint 与 :636 精确匹配。这里不仅有 shader 名称，还有实际 dispatch、有效常量、参数数据和资源使用证据。

粒子 Kill/Compact/Swap 的部分字节码在 Dirt 与 Gravel 对象间完全相同，因此导出标签 `Dirt_*` **不能唯一证明对象归属**。完整汇总记录所有候选；可确认共同核体和调用，不据名称恢复工具业务流程。

test42 只匹配到 Readback.Update E524、Ground.UpdateObstacleHeight E3011 等；没有 Ground.Paint / Water.Paint。该帧可作“没有出现本次编辑核”的对照，不足以证明游戏暂停、没有操作或某个生命周期阶段。

## 沙笔刷的有效形式

Ground.Paint 是全域 dispatch：32×16 组，每组 32×32，共 **524288 个线程**覆盖 1024×512 沙床。它通过纹理 alpha、空间变换和形状范围决定局部效果，不能说竞品已采用局部脏区 dispatch。

有效参数：mode cb141.z=3，中心 `(4.588698, 0.723059, 5.844068)`，印章缩放约 `(1.2,1.2,1.2)`；32 字节 brushData 为 `(0,0,0,0,0,1,0,0)`。印章 `ResourceId::578` 为 256×256 RGBA32F（1 MiB），RGB 相同，R 范围 0–0.835126，alpha 范围 0–1。这是高度纹理印章，不是 CPU 上传的逐格沙高列表。

沿实际 mode=3 的 shader 分支，令 `M` 为范围/alpha/衰减形成的权重，`R` 为印章红通道，沙高趋向 `center_y + 1.2 × (2R−1)`，再限制在有效高度范围。这个模式含降低区域的可能，不等同于严格按指定体积只加沙；原作库存与体积策略未知。

原始 before/after 导出最初出现大范围差异，进一步负例证明：在**同一个 replay controller** 中反复 SetFrameEvent 会带来额外状态变化，不能把整图差分都归于笔刷。改为每个快照重新打开捕帧后，同事件高度差仅 115/130 格、最大 2/1 个编码单位且在几何笔刷区域外。两组独立前后对照在区域内均得到 **732 格完全相同的高度变化**，范围 `(653,439)–(683,471)`，最大编码变化 1339132。区域外仍有 ≤2 编码单位的重放/重编码差异，保留反证，不以整图差分统计移沙体积。

## 专用水编辑：对“水快速散开”的新证据

**E878，mode=2：重设量字段。**cb138=(2,1,0,0)，36 字节参数的 amount 分量为约 0.045，其余为 0；gain override=1。Water.Paint 反汇编第 228–247 行结合前面的实际模式选择，将 amount 字段按权重趋向 0.045 并重新编码。它不是单纯保留水量、抬高床面。区域内前后记录有 403 格 amount 编码变化；这不是整个场景守恒验收。

**E1210，mode=6：显式修改速度。**cb138=(6,0,0,0)，参数速度分量为 `(5,5)`，amount 分量为 0。反汇编第 164–167、215–219 行给出实际速度更新：

`v_new = v_old − M × G × 5 × n`

其中 `n` 是从笔刷中心指向采样点的水平分量，归一化长度还包含中心 y；`G=(2R−1)×1.2`，是**有符号的印章增益**。因此不能把它描述成处处恒定向外的冲量；不同纹理区域可以有不同方向。这帧明确包含专用速度编辑，提供了显式速度驱动（指令/有效参数 C3；对实际画面快散开的因果贡献和秒级速度仍 C0，适配效果为待验证假设 C1）。

此前 UpdateFloor 保留 amount 的结论在所测常规核中仍成立；test41 新证据说明不能据此排除编辑阶段的专用处理。包内另有 SubtractFloor / CopyGroundHeight 等核，本帧没有匹配到，不能把名称对应的算法加入本帧链路。

原作全水量守恒、被重设的水量如何结算/去向、速度分量的物理单位仍未知。**不能把 0.045 和 5 直接移植成正式参数，也不能在本项目中用删水假装排水。**Godot 适配需在局部排水、动量响应和现有守恒契约之间明确语义。

## 对当前性能的判断与适配

当前项目基本链路仍是 GPU 沙场 → 最新 CPU 影子解码/校验 → CPU 守恒笔刷 → GPU 绝对 patch。test41 则在 GPU 使用印章/少量参数直接编辑现有场，随后更新切线、水与粒子，再让 GPU 状态直接参与绘制。**可借鉴的是把可见编辑计算留在 GPU，减少“必须等最新整图影子到 CPU 才能编辑”的依赖。**这帧 Readback.Update 在编辑之后，不能是本帧这些笔刷的先决数据；原作是否消费上一帧 CPU 读回仍未知。

收益不能凭单帧宣称：竞品其实有整域 dispatch 和多轮粒子 pass，没有证据证明原作零读回/零等待，也没有原始真实动作的 CPU/GPU 毫秒数。当前正式入口显式沙校验已移入工作线程，最新20笔最大60.818 ms；预取回调仍在主线程全图校验，同逻辑完整成本 p99 36.937 ms 仍未过。详见此前报告和已保存原始计时。

建议先定位正式入口预取/同步/发布各阶段，再验证 GPU 原生守恒笔刷：少量命令参数 → 局部权重与可移量归约 → 权威 GPU 沙场更新 → 小型结果结算，碰撞按脏 chunk 更新，恢复在一致 tick 边界取完整状态。局部 dispatch、小型体积归约、库存预留及碰撞调度都是本项目适配，不能冒称竞品已确认实现。水编辑需另有守恒 ADR 与负例验证。本专项未修改正式模拟或性能门槛。

## 证据与复验

机器目录：`evidence/edit_performance_test41_test42_20261010/`。

- [完整汇总](../../task/sandcastle_test1_reverse_rebuild/evidence/edit_performance_test41_test42_20261010/analysis_complete_summary.json)：两帧核匹配、实际参数、原始字节定位、变体歧义与边界。
- `runtime_retry_1/`、`effects_runtime/`：原始 runtime DXBC、常量、ground/water/readback 完整已选 buffer 快照；未导出的粒子字段不宣称恢复完整。
- `effects_package/`：Water、Dirt、Gravel 对象原始字节、typetree 与 54 个包内编译变体。
- `replay_control_fresh/`：每次重新打开捕帧的4份沙场及印章原始纹理；`water_paint/`：E877/878/1209/1210 水状态和两次实际参数。
- [溯源校验](../../task/sandcastle_test1_reverse_rebuild/evidence/edit_performance_test41_test42_20261010/provenance_validation.json)：源 hash、导出 hash、数量、偏移/长度、失败/部分运行记录。

复验用 RenderDoc 1.46 执行相应 `tools/investigate_edit_rdc_test41_test42_retry.py`、`investigate_edit_effects_rdc.py`、`probe_edit_paint_replay_fresh.py` 与 `probe_edit_water_paint.py`，写新英文 run 目录；包内由 UnityPy 1.25.4 / D3DDisassemble 导出。原始失败脚本/manifest 和同 controller 反例保留，不能用后来成功抹掉。
