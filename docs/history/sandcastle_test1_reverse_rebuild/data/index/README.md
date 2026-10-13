# 数据索引入口

当前：**P01索引已生成并通过RG1原始取数验收。**数量、限制与复验见[RG1报告](../../验收/RG1_拆包索引与原始取数.md)。

任务根：`D:/godot/project/sandcastle/task/sandcastle_test1_reverse_rebuild/`。原包：`D:/godot/project/sandcastle/sandcastlegame/`。

## 从一个效果找到原始数据

1. 查`assets.jsonl`：按名称/类型找到全部候选，确认源文件和PathID；不要只按名字选第一个。
2. 顺`dependencies.jsonl`：材质→shader/纹理/配置，scene→renderer/组件。
3. 用`raw_path`取得对象字节；有`stream_ids`再从`payloads.jsonl`取得`.resS/.resource`中的外部数据。
4. `decoded_paths`提供可读JSON/图/模型/反汇编，每个派生文件回指raw ID。
5. 查`asset_rdc_mapping.jsonl`：查运行时对应资源以及映射可信度；运行时生成资源可能无包内对象。
6. 查`rdc_events.jsonl`和`bindings.jsonl`：找到有效事件、stage、slot/space、buffer/texture/常量快照。
7. 用`source_files.jsonl`及`artifacts.jsonl`复核来源hash和取数方法；`tools.json`与日志提供复跑环境。

## 索引文件计划

| 内容 | 位置 | 原始数据/可读数据位置 |
|---|---|---|
| 原文件与来源身份 | source_files.jsonl | 原包只读路径；需要时经hash核验副本 |
| 序列化对象目录 | assets.jsonl | `../raw/assets/` / `../readable/assets/` |
| 外部纹理/网格payload | payloads.jsonl | `../raw/assets/<source>/payloads/` |
| 对象引用 | dependencies.jsonl | from/to ID和field path |
| 视觉配置及有效参数映射 | visual_config.jsonl | 资源字段raw/decoded路径与RDC绑定 |
| 必要视觉类型/字段（按需） | symbols.jsonl | `../raw/il2cpp/` / `../readable/il2cpp/`；不包含方法体或业务分析 |
| test1绘制/dispatch | rdc_events.jsonl / rdc_action_io.jsonl / rdc_snapshots.jsonl | `../raw/rdc/test1/` / `../readable/rdc/test1/` |
| 有效常量/纹理/buffer绑定 | bindings.jsonl | raw/decoded路径与格式/stride |
| 包内→RDC映射 | asset_rdc_mapping.jsonl | 证据ID和confidence |
| 派生产物与工具 | artifacts.jsonl / tools.json | run_id、hash、command_ref |

## 查询与取数

以下工具已由P01 G05实现并复验：

```powershell
$planRoot = 'D:/godot/project/sandcastle/task/sandcastle_test1_reverse_rebuild'
python "$planRoot/tools/query_index.py" --root $planRoot --kind asset --name 'Lit/Whitewater'
python "$planRoot/tools/query_index.py" --root $planRoot --kind rdc --capture test1 --event 6196
python "$planRoot/tools/get_raw.py" --root $planRoot --id '<查询得到的稳定ID>' --out "$planRoot/evidence/retrieved.bin" --verify
python "$planRoot/tools/validate_index.py" --root $planRoot
```

若输出`raw_only`，数据存在但解释未完成；`failed`须看error；RDC仅有重放定位时返回`replay_required`及脚本选择器。PNG、OBJ、反汇编和伪代码是可读/派生产物，不是原始字节。

完整字段及失败语义：[原始数据与索引契约](../../契约/原始数据与索引契约.md)。
