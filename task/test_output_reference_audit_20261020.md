# `test_output` 引用核对（2026-10-20）

## 盘点结果

仓库内实际目录名是 `test_output`（不是 `test_ouput`）。盘点到 258,722 个文件、103,437,275,904 bytes。目录级 `.gitignore` 忽略所有产物；`.gdignore` 将此目录排除在 Godot 扫描之外。

仓库外部共找到 2,928 行包含 `test_output/<path>` 或 Windows 分隔符路径的文本引用。逐行来源、行号和原文见 [test_output_references_20261020.csv](test_output_references_20261020.csv)。该索引包含代码、测试、资源、文档、历史记录和任务文件；路径出现不等于运行时读取。

## 必须保留的固定输入

- `unified_edit_pipeline/g0_function_baseline01/regression_all_tools_1.sandgp` 与 `gpu_pipeline/g7_20261017_03/migration.sandcp`：配置迁移探针及资源索引读取。
- `unified_edit_pipeline/g0_final_reference_20261018/reference_sources.zip`、`g8_cost_joint02`、`g8_architecture_final01` 和 `g8_formal_frozen01` 下的报告/封存数据：交付封存和回归脚本读取。
- `floating_props/baseline_20261018_01/baseline.sandue`、`packed_parallel_20261018` 与 `velocity_prepare_parallel_20261018` 下的验证 JSON/ZIP：原生来源目录生成与迁移探针读取。
- `gravel_drop_20261016_v2/{main,test1_backwash}.sandcp`：迁移探针输入。
- `competitor_water_material_20261011/replay_v5/event_5006_ps_texture_1105_mip0.bin` 和 `water_material_rdc/caustic_mips_v1/manifest.json`：材质导入脚本读取。
- `shape_brushes` 下的固定 continuation、retention、material-damage 夹具，以及 `water_material_natural` 下被分析/候选生成脚本读取的早期结果。
- `unified_edit_pipeline/g6_presentation_final01` 的 bake 图像和 manifest、`test1_geometry_20261018/replay_v3` 的 buffer，以及 `test1_water_motion` 的 capture/package manifest：资源配置或状态构建脚本读取。

## 仅作为未命中候选的目录

下面目录没有发现仓库文件中的 `test_output/<目录名>` 路径或目录名提及；这只是静态检索结果，不足以证明其中的独立历史证据没有价值：

- `drainage_toggle_20261018`
- `editor_profile_fix_20261012`
- `export_pack_probe`、`export_verified_probe`
- `frame_redundancy_fix_20261014`、`frame_redundancy_review_20261014`
- `gravel_drop_20261016_v1`
- `shovel_stutter_20261018`
- `suspended_sand_20261016_v1`
- `ui_sand_edit_20261016_v2`
- `water_material_consistency_20261013_v1`
- `scene_lifetime_20261013_baseline`、`scene_lifetime_20261013_baseline_v2`、`scene_lifetime_20261013_baseline_v3`、`scene_lifetime_20261013_current_v1`、`scene_lifetime_20261013_current_v2`、`scene_lifetime_20261014_baseline_v4`、`scene_lifetime_editor_backup_20261013`

`scene_lifetime_20261014_final_v1` 被任务核对记录提及；免费工具和场景切换的若干目录被验收脚本/ADR 按目录名读取，因此不列为候选。`prop_placement_20261019` 的同名内容被任务记录指向外部可视化目录；仓库内同名目录与该外部目录并非同一绝对路径，故保守保留。

## 处置状态

本轮没有删除文件。对上述候选目录执行递归删除时，命令被本机自动审查策略拒绝（`exec_command` 返回 `blocked by policy`）；未尝试绕过该拦截。目录清单、字节数和文件数已在删除前核对，可用于后续清理决策。

需要区分：脚本中的 `OUT`、`output`、`save` 目标大多只说明新结果写到哪里；引用索引中凡是写入目标都不能据此认定旧文件是输入依赖。反过来，文档和任务中的历史证据链接即使没有代码读取，也可能仍服务于复验和出处追溯。
