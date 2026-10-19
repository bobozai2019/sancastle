# Sandcastle 项目文档

项目使用Godot 4.7.2和统一沙水流程。正式入口为main、test1_capture、test1_backwash和test1_geometry；默认运行`scenes/main.tscn`。

## 技术文档

| 文档 | 内容 |
|---|---|
| [当前项目技术方案](当前项目技术方案.md) | 技术栈、模块职责、GPU编辑与模拟、渲染、碰撞、存档 |
| [当前技术规格](当前技术规格.md) | 单位、字段、ABI、容量、算法参数、事务与兼容性 |
| [主场景操作](主场景操作.md) | 工具、水响应开关、力度、相机、暂停和保存恢复 |
| [场景切换与功能复用](场景切换与功能复用.md) | 四个正式入口、场景差异、会话进度和场景接入 |
| [玩法扩展指南](unified-edit-extension-guide.md) | 类型化profile、模板与配置扩展 |
| [漂浮道具](漂浮道具.md) | 公共只读采样、Jolt、道具摆放与消费者约束 |
| [性能面板](性能面板.md) | 窗口统计、队列、在途和完成态口径 |
| [交互式执行指南](project-execution-guide.html) | 执行阶段、源码锚点及[来源索引](project-execution-guide.sources.json) |

main默认使用动量B：按实际床面差施加推拉动量，编辑阶段保持水深和悬沙，后续由常规水流模拟搬运。面板保留原连通排水开关和力度设置；三个test1入口默认连通排水。公式与参数见[编辑水响应规格](当前技术规格.md#编辑水响应与主场景开关)。

## 文档维护

当前技术文档按主题描述生效实现，不记录开发经过、移植过程、任务进度或验收流水。写作规则见项目根目录[AGENTS.md](../AGENTS.md#项目技术文档规范)。修改源码后同步方案、规格和操作说明，再运行`python -X utf8 tools/docs/build_execution_guide.py`及`--check`。

[可复用契约](knowledge/README.md)约束数值、源汇、碰撞和恢复；[竞品技术知识](competitor/README.md)单独记录来源事实与适用范围。[历史文档](history/README.md)不作为当前实现的说明入口。
