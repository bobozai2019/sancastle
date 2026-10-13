# RG1 拆包索引与原始取数验收

日期：2026-10-10（Asia/Shanghai）。判定：**通过，带明确未解项**。本报告只验收原始数据可取得和索引可复验，不判定算法或画面效果。

## 来源与工具

- `sandcastlegame/` 全部38个文件、2,566,443,298字节已在 [`source_files.jsonl`](../data/index/source_files.jsonl) 登记；[`g01_summary.json`](../evidence/g01_summary.json) 和 [`g05_index_validation.json`](../evidence/g05_index_validation.json) 证明源文件前后SHA256一致。主 `test1.rdc` SHA256为 `761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2`，与 `rdc/test1.rdc` 副本相同。
- Unity版本字符串 `6000.4.10f1`，序列化版本22，IL2CPP metadata版本39。UnityPy 1.25.4、RenderDoc 1.46 `e4bd23b671d3d5a747ff5221dbe08a63eb6ca200` 的路径、二进制SHA256、命令和探针见 [`tools.json`](../data/index/tools.json)。

## 核验结果

| 项目 | 结果 | 证据 |
|---|---:|---|
| Unity容器对象 | 5个容器，16,714个对象全登记，原始对象字节逐个等于源文件对应范围 | [`g02_object_extract.json`](../evidence/g02_object_extract.json)、[`g02_validation.json`](../evidence/g02_validation.json) |
| 外部payload | Texture2D/Texture3D/Mesh的460段均单独导出并与`.resS`字节范围比对 | [`payloads.jsonl`](../data/index/payloads.jsonl)、[`g02_validation.json`](../evidence/g02_validation.json) |
| 引用与可读数据 | 14,256条材质/场景/渲染器等PPtr边，14,218条本文件解析；4个P0材质及8个直接依赖可读导出 | [`dependencies.jsonl`](../data/index/dependencies.jsonl)、[`g02_visual_closure.json`](../evidence/g02_visual_closure.json) |
| 视觉配置 | 4个材质的160个包内默认字段可读；8个相关MonoBehaviour只保留raw和通用前缀，状态为`raw_only` | [`visual_config.jsonl`](../data/index/visual_config.jsonl)、[`g03_visual_config.json`](../evidence/g03_visual_config.json) |
| RDC运行时 | 1,686条action，1,546条draw/dispatch的输入输出资源ID；9个P0事件详细绑定，P02增量后85份原始快照 | [`g04_summary.json`](../evidence/g04_summary.json)、[`rdc_snapshots.jsonl`](../data/index/rdc_snapshots.jsonl) |
| 索引和复取 | P02增量后17,426条产物溯源，整体验证通过；8个正例和1个未知ID负例通过 | [`g05_index_validation.json`](../evidence/g05_index_validation.json)、[`g05_retrieval_test.json`](../evidence/g05_retrieval_test.json) |

`test1`事件 3867→3872 的256×128纹理、底面/水面/白沫后1280×720 HDR、2048²深度、两个1920×1080交换链buffer均保存了原始快照。4956/4980/5006、6069/6083/6151及6196的VSOut都已提取；6196覆盖29,950个实例。RDC快照是RenderDoc API返回字节，未宣称GPU物理显存排布；反汇编不是原始HLSL。

## 复跑入口

```powershell
$root = 'D:/godot/project/sandcastle/task/sandcastle_test1_reverse_rebuild'
python "$root/tools/query_index.py" --root $root --kind asset --name 'Lit/Water'
python "$root/tools/query_index.py" --root $root --kind rdc --capture test1 --event 6196
python "$root/tools/g05_retrieval_test.py"
python "$root/tools/validate_index.py" --root $root
```

按查询返回的精确ID调用 `python "$root/tools/get_raw.py" --root $root --id '<ID>' --out "$root/evidence/retrieved.bin" --verify`。已有输出不会覆盖；源文件SHA256不符、范围越界、ID不存在或RDC快照缺失均返回非零及错误码。复验产生的样本在 [`evidence/g05_retrieved`](../evidence/g05_retrieved)；每项结果与命令见上述测试JSON。

## 未解项与后续入口

1. 38条跨文件PPtr边仍标 `external_file_index`，均为机械索引未解引用；当前四个P0材质的直接shader/纹理引用均已解析。P02追踪场景视觉组件时若遇到这些边，须先按容器external表补映射。
2. 8个视觉MonoBehaviour的自定义字段没有可靠typetree。原始对象和脚本指针已保存；运行时有效值须从RDC常量、纹理和buffer查证，不把原始字段未知当作零值。
3. P02新增取证后，包内`Sand`二维纹理与RDC `ResourceId::617`的解码mip0经上下翻转逐字节相同，映射为C3；其余28项包内资源→RDC资源映射仍为C0 `unmapped`。名称相似不能建立同一性，须按格式、尺寸、内容或绑定补证。
4. 两个最终交换链buffer均已保留；Present事件6645指向`ResourceId::427`，其RGBA8无校色预览见[`event_6645_present_427.png`](../data/readable/rdc/test1/event_6645_present_427.png)。RDC action的资源ID目录覆盖所有draw/dispatch，详细寄存器绑定只针对9个P0事件。

上述未解项已在索引和本报告显式登记，不影响从源文件及捕帧按精确定位复取P0原始字节。RG1通过；P02仍须逐条评估结论可信度。
