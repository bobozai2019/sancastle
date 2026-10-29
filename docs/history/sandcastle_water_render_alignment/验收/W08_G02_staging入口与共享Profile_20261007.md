# W08 G02 staging 入口与共享 profile（2026-10-07）

结论：新增一份严格校验的 staging profile、固定/耦合两个可直接启动的场景，以及从同一 loader 读取 profile 的捕图路径。D3D12/GTX 1050、真实 1920×1080、tick30 的两模式均确认直接入口与 profile 捕图的 requested/effective SHA256、水深 F32 和俯斜 PNG **完全一致**。这是 W08 G02 的入口接线证据，不是 WR-G0/V01–V08、最终性能或 release profile PASS。

## 实现边界

- [staging profile](../../../../tests/visual_water_alignment/prototypes/water_render_staging_v1.json) 只标记现有原型已接线的 eta 法线、屏幕光学、主水面白沫、折叠亮纹和局部前缘；反射、岸线接触和亮沫片为 `pending=false`。`implemented` 表示代码路径存在，不表示视觉已验收。
- [唯一 loader](../../../../scripts/visual/water_render_profile.gd)严格检查字段、版本、域参数、固定/耦合 fixture、资源路径、效果状态、参数范围与依赖；staging 水面偏置固定为原入口实际使用的 **0.003 m**。有效配置由同一方法从运行时材质回读并哈希。
- [直接入口脚本](../../../../scripts/visual/water_render_staging_entry.gd)由 [固定场景](../../../../scenes/water_render_demo.tscn) 和 [耦合场景](../../../../scenes/water_render_coupled.tscn) 共用。它在场景初始化前加载配置，在 GPU 准备完成后核对材质有效值，表现时钟只由完成 tick 更新；暂停后时间不前进。旧 `main.tscn` 和旧夹具未改。
- [捕图器](../../../../tests/visual_water_alignment/prototypes/capture_reference.gd) 的显式 `--profile=` 路径读取同一 loader，禁止同时传视觉 CLI 覆盖，并记录 requested/effective profile SHA256、运行时材质参数和资源。普通未传 profile 的原型入口仍保留。

## 结果

配置解析探针 exit 0，报告有效 profile 通过、九种错误配置均按预期拒绝：未知字段、错误版本、域参数、缺资源、启用 pending、越界视觉值、0.006 m 偏置漂移、依赖不一致和缺必填字段。profile SHA256：`b35b81cbd5831a48c361c98e8737096d7b5badd70db955429d5703cde179d8a7`。

| 模式 | fixture | 初始 rock/sand/water 哈希 | tick / revision / 表现时间 | 直接入口与捕图 |
|---|---|---|---|---|
| 固定 | `water_render_demo_v2` | `639217814/1069331530/774098242` | `30 / 90 / 1.0s` | requested/effective SHA、水深 F32、俯斜 PNG 全同 |
| 耦合 | `water_render_coupled_v2` | 同上 | `30 / 90 / 1.0s` | 同上 |

两模式的有效配置 SHA256 分别为固定 `344e60bccc0675b737b8cb5043a4aa6bdfd3f81a81886f2f997d97baf2417cfa`、耦合 `3a2a9c079fc9476e711ab855e9310be50c8e09f69af4c7838c94fdd8257998dd`，差异含 fixture 与床面 shader；各模式内部两入口相同。截图逐像素一致，水深文件逐字节一致。[复算 JSON](W08_G02_staging入口_20261007/staging_entry_metrics.json)及[复算脚本](W08_G02_staging入口_20261007/analyze_staging_entry.py)保留逐项断言。

受控负例：在 `--profile=` 后混入 `--eta-normals`，捕图器退出码 1，日志为 `profile mode forbids visual CLI override`，未生成 manifest。正常直接入口及两次 profile 捕图均退出 0、报告 PASS，日志无 shader/script ERROR；已有 `Image.load_from_file` 的 PNG 导入警告仍在，正式导出前需处理。

另以 `--quit-after 120 res://scenes/water_render_demo.tscn` 和对应耦合场景作为 Godot 主场景直接启动；两者退出码均为 0，日志无 shader/script ERROR。此短启动只证明新场景可直接进入，不证明录像或长期动态。

短暂停/恢复探针在两个新直接入口各运行至 tick30，暂停并等待 30 个实际绘制帧；暂停前后 PNG SHA256 相同，tick 均保持 30、表现时间均保持 1.0s。恢复后均到 tick31、表现时间 1.033333s，与 `tick/30` 相符。该结果只覆盖约半秒暂停和一次继续，不代替检查点恢复、长时间录像或活跃白沫恢复。

曾发现新 profile 误把 shader 默认偏置 0.006 m 当成原入口有效值。两种入口的水深文件当时已相同，但俯斜图有 895/1,280 个 >12/255 差异像素；统一参数快照定位到原入口实际覆盖为 0.003 m。改回后两模式图像完全一致，并将偏置漂移列入 loader 负例。旧错误样本保留在证据目录，不纳入最终 PASS。

## 尚未完成

W08 G02 的录像和成本探针现已接入同一 loader，见[接线烟测](W08_G02_staging录像成本接线_20261007.md)；仍需验证直接演示长时间动态、检查点恢复及存档中的 profile/表现时钟；本轮只有短暂停与一次继续。G01 仍缺湿度与局部前缘等效果的可见消费核验；G03 的资源缺失、旧产物和字段异常等端到端负例未齐。当前 W07 的 V01/V03/V04/V06/V08 与 WR-G0 保持未通过，按十轮规则不在 W07 继续性能调参。staging 场景不得作为 release 入口验收。

复现（工作目录 `D:/godot/project/sandcastle`）：

```powershell
$out = (Resolve-Path 'task/sandcastle_water_render_alignment/验收/W08_G02_staging入口_20261007').Path
& 'D:/godot/Godot_v4.6.2/godot.exe' --headless --path . --script res://tests/visual_water_alignment/prototypes/probe_staging_profile.gd
& 'D:/godot/Godot_v4.6.2/godot.exe' --path . --rendering-driver d3d12 --fullscreen --resolution 1920x1080 --disable-vsync --script res://tests/visual_water_alignment/prototypes/probe_staging_entry.gd -- "--output=$out" '--run-id=staging_final30'
& 'D:/godot/Godot_v4.6.2/godot.exe' --path . --rendering-driver d3d12 --fullscreen --resolution 1920x1080 --disable-vsync --script res://tests/visual_water_alignment/prototypes/probe_staging_entry.gd -- "--output=$out" '--run-id=staging_pause30' '--pause-test'
& 'D:/godot/Godot_v4.6.2/godot.exe' --path . --rendering-driver d3d12 --fullscreen --resolution 1920x1080 --disable-vsync --script res://tests/visual_water_alignment/prototypes/capture_reference.gd -- '--case=water' "--output=$out" '--run-id=profile_final_fixed30' '--tick=30' '--profile=res://tests/visual_water_alignment/prototypes/water_render_staging_v1.json' '--require-1080p' '--write-water-field'
& 'D:/godot/Godot_v4.6.2/godot.exe' --path . --rendering-driver d3d12 --fullscreen --resolution 1920x1080 --disable-vsync --script res://tests/visual_water_alignment/prototypes/capture_reference.gd -- '--case=coupled' "--output=$out" '--run-id=profile_final_coupled30' '--tick=30' '--profile=res://tests/visual_water_alignment/prototypes/water_render_staging_v1.json' '--require-1080p' '--write-water-field'
python 'task/sandcastle_water_render_alignment/验收/W08_G02_staging入口_20261007/analyze_staging_entry.py'
```

当前源码 SHA256：profile `B35B81CBD5831A48C361C98E8737096D7B5BADD70DB955429D5703CDE179D8A7`；loader `A1D6C1B84D8794D86A0607582E2C790C119F6C11215C4A65D04F7611E92A8282`；入口脚本 `0B78923F55A852212F28DFA58742D4645AE958707998C7407B3236B3B6D5C48E`；捕图器 `DAD9DD9B4CA33B44FC9471F24A28D56E76C27F7B8766E80512EF9A2758637AE9`；直接入口探针 `2C1E6FE458412000C5571658C81B0CAF5C4D23FAE7BCE8F7A27CD41E01E99C95`；复算脚本 `7A8BF703325D87136BEB09FC8CBFF4D37B0E60D51A4871C9A4F3D992E516E54B`。
