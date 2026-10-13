# T03 GPU 沙笔刷：矩阵、事务负例与局部派发

日期：2026-10-11。角色：acceptance_evidence。T03仍进行中，G2暂未放行；本报告只判定已覆盖的候选行为。默认入口未切换，旧性能FAIL保持。

## 证据与判定

| 运行 | 内容 | 结果 |
|---|---|---|
| [021743](../evidence/20261011_021743_scenes/gpu_brush_matrix.json) | 原全域候选，64²/256²共162项 | PASS |
| [022732](../evidence/20261011_022732_scenes/gpu_brush_matrix.json) | 新窗口参数接口，全域模式，同一162项 | PASS |
| [022817](../evidence/20261011_022817_scenes/gpu_brush_matrix.json) | 同一shader/初态/命令，局部窗口模式，162项 | PASS |
| [全域/局部二进制对照](../evidence/20261011_022817_scenes/full_local_equivalence.json) | 454份同名bin：沙、CPU参考、命令、回执、初态/seed | 全部SHA256相等 |
| [022200事务失败](../evidence/20261011_022200_scenes/receipt_failure_probe.json) | GPU条件提交之后、请求回执之前注入运输失败 | 11字段含显示沙面逐位不变，库存/revision不变，预留释放，后续拒绝 |
| [022200迟到回调](../evidence/20261011_022200_scenes/late_callback_probe.json) | backend.release后合成调用旧回调 | 回调未转发；不代表真实在途退出覆盖 |

每个scene运行保存manifest中的源码/引擎hash、实际D3D12参数、原始bin、stdout/stderr和artifact_index。全域/局部对照文件在运行后追加，内含全部比对对象的hash。可通过启动器`-Matrix`及`-Matrix -LocalDispatch`重跑；该窗口是960×540的数值验证，不是成本门。

矩阵覆盖：均匀0.4m沙、混合薄沙、无沙；0.25/0.75/4m圆形挖堆；扫掠和退化线段；域边/角落；零强度、不足库存、临界EPS连续放沙；同tick连续命令、重复ID、旧generation/stale tick、未来命令的due执行器拒绝；NaN/Inf；GPU→旧smooth/compact→GPU；GPU层绕过host后的旧代/旧revision/非有限拒绝；64bit ID/代际/tick/ticket与revision低32位进位。

每笔按冻结沙误差预算对照CPU，核对实际GPU沙变化与回执/桶账户、非负有限、区域外逐位不变、dirty chunk边界扩张；dig/place的其他9权威字段逐位不变。64bit极值是运输测试，不声称已经模拟了对应tick时长。compact按原生RF→RH编码逐位对照，原因及原失败见ADR v1.2。

## 实现与适用范围

prepare在GPU计算原工具权重；固定行优先Kahan归约与原4轮挖沙分配；独立候选缓冲、条件提交、128byte实际量回执；CPU结算完成后才复制到独立显示沙面。沙提交同时更新两个物理ping-pong沙纹理，失败从候选before回滚两个物理沙面。回执或发布未完成时拒绝新的直接派发。

局部模式只在CPU由wire中的float32端点/半径计算包围矩形，额外外扩两格；权重、四轮分配、量审计与提交仍在GPU。归约遍历窗口时保留同一非零格的行优先顺序，跳过窗口外零权重；不读取陈旧的窗口外candidate。publish仍是全域GPU复制。本次只改变派发范围，未同时引入并行归约或发布优化。

局部模式依赖已完成态的全域沙有限/非负不变量。它只审计被准备的窗口，不能以本矩阵证明检测窗口外的独立资源损坏；严格恢复/全域审计在后续恢复门另验。现阶段默认候选仍用全域模式，局部收益留给T06测量。

022540 headless导入已输出四shader导入完成，但进程退出码非零，保留为失败。后续两次真实可见RD运行成功加载并执行实际shader；不把导入日志当验收PASS。

## 已发现问题与契约版本

- 临界负库存必须保留signed balance，不能max(0)重开每笔EPS；[ADR v1.1](../契约/ADR_临界库存与旧工具回退_v1_1.md)及16项codec探针、连续临界库存样本覆盖。
- 旧compact的0.5 ULP16舍入假设不适用，015841失败保留；独立原生编码逐位证据后采用[ADR v1.2](../契约/ADR_旧compact的R16编码验证_v1_2.md)，没有改宽沙/水量预算。
- 释放backend后忽略合成迟到回执；真实pending退出仍属于T05。

## 未完成

T03 G01权重/4轮归约、G02候选/条件提交/小回执已有本报告证据。G03继续核对覆盖边界：很厚沙上的低于float32高度分辨率的微小放沙尚未测试，当前量预算代码只累计changed cells，与冻结公式的touched footprint可能不一致，须先用原始样本辨别而不能直接放宽容差。

容量64待排队、真正未回执的快速重叠输入、真实在途退出、碰撞反馈、撤销/检查点属于T05，当前同步due执行器不冒称覆盖；水策略T04和完整性能/长稳T06均未开始。G2在剩余沙数值边界核验和范围复核后判定。
