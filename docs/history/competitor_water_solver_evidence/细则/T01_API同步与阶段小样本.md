# [已完成] T01 API同步与阶段小样本

角色：task_spec。负责人：主执行者。进度：4/4小目标。依赖：T00／G0。验收出口：G1。

需求：R02、R03、R11。契约：C01、C02，见[契约入口](../契约/README.md)。状态回填[执行状态](../执行状态.md)，实际结果进入[验收](../验收/README.md)。本文件描述计划，不记录运行通过。

## 输入

T00来源、环境和pilot请求；[shader导出器](../../../docs/competitor/tools/export_shader_execution_audit.py)、[旧水核导出器](../../../tests/investigation/test1_water_motion/export_capture.py)、[全流程分析](../../../docs/competitor/水处理全流程与项目对比.md)。旧工具行为须核对后复用。

## 小目标与完成条件

| ID | 状态 | 小目标 | 完成条件 | 预期产物 |
|---|---|---|---|---|
| T01-G01 | [已完成] | 程序与绑定 | 匹配capture hash后定位E1495水量核，核对程序字节、SRV／UAV／常量、线程与dispatch规模。 | pilot_program及binding manifest |
| T01-G02 | [已完成] | 同步依赖图 | 覆盖水核链的完整API范围，导出resource barrier、queue、Signal／Wait和读写依赖。 | sync_graph.json，原始API证据 |
| T01-G03 | [已完成] | 阶段小样本 | 保存水量核实际输入依赖与输出字节；明确前／后边界取得方法和不能证明的配对项。 | snapshot manifest，完整性表 |
| T01-G04 | [已完成] | 全核选择器 | 建立六类核及三轮实例选择器并审阅G1；不把裸事件号跨捕帧复用。 | stage_map.json，G1报告 |

真实产物、hash、边界及部分／失败记录见[G1](../验收/G1_20261025.md)。

## 执行步骤

1. 从一个E1495候选开始，在匹配test1身份之后检查实际绑定，不先批量导出全帧。
2. 同时读取dispatch之间的API，不以RenderDoc action tree代替完整同步记录。包括相关跨队列依赖与资源别名。
3. 记录SetFrameEvent等API的真实边界语义；无法取得原dispatch前态时输出unproven。
4. 建立UpdateFloor、速度、水量、平流、源汇、法线六类映射；E1484／1490／1495／1500／1537／1543只作为经hash核对后的初始线索，三轮的每个实例分别定位。

## 验证与失败出口

每个导出有选择器和完整字节范围；至少一个核的依赖可复验，屏障证据可定位。错shader／资源映射负例须失败。前后配对未证实可以进入T02诊断，但不能凭此进入公式误差判定；实际读依赖缺失须补齐或明确阻塞。

## 文件归属与写锁

本任务tools／requests和新evidence run；原shader、原RDC不改。保留工具源快照及日志。

开始前在执行状态登记GPU／共享文件占用；完成后释放。所有必要证据写入唯一run目录，保留失败，不覆盖旧产物。

## 工具与命令

可复用导出器通过SHADER_AUDIT_OUT和SHADER_AUDIT_SELECTION配置；执行前核对实际读取方式。完整API同步导出能力需实现／验证后才提供命令，不假设旧脚本已有该能力。

