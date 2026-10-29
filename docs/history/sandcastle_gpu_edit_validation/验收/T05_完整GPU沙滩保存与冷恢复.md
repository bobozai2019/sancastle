# T05 完整 GPU 沙滩保存与冷恢复

2026-10-11。Godot4.7.2/D3D12/GTX1050，1920×1080可见完整原负载。evidence目录含manifest/源码与资源hash、原始物理和视觉bin、PNG、完整prefix/五账本Variant bytes、日志和artifact_index。成本门未判定。

命令：run_scene_probe.ps1 -BeachEditProcess -CheckpointMode write；独立读进程追加-CheckpointMode read -CheckpointSource对应目录。固定原负载至tick15，真实GPU E dig 0.01 m³、C place 0.005 m³，ID9007199254741103/1104；原耦合两tick后保存tick17，恢复再继续七tick至24。

080344_scenes写成功，080409_scenes读FAIL：测试脚本将无类型空Array赋给带类型replay_prefix_commands，未进入恢复；watchdog退出记录泄漏。修正为clear既有带类型数组。080927_scenes是追加诊断中的局部变量类型推断编译FAIL；修正显式String，原日志保留。

080707_scenes写、080728_scenes读：cold preflight四负例通过；tick17的十五份当前物理/视觉bin、PNG、五账本、完整prefix及原int64高水位逐位相同。继续tick24后sand/bed_0不等，沙四格分别一ULP，最大5.9604645e-08；其余字段相等。此继续判定FAIL，原结果不覆盖。

080938_scenes写、081008_scenes读：诊断模式额外读取八备用物理槽并逐tick取数，备用槽与索引、十五字段/像素、七个中间完成态、五账本和prefix全部配对。实际cohesion=0、每tick两子步、当前槽一致。该额外取数结果不能证明原低取数路径无问题。

081139_scenes写、081204_scenes与081238_scenes两个独立读：关闭额外备用槽/逐tick取数，当前默认探针tick17及tick24的十五bin、PNG、五账本、完整prefix和原int64高水位逐位一致；四结构负例均拒绝（配置、账本投影、receipt身份、非零pending）。这两次通过是当前边界的直接证据，但并未解释080728的一ULP失败。探针将七tick逐个await调用，早期批次调用一次advance循环；没有以观察相关性认定因果。

完整恢复G4保持未放行：还需活动scene隔离原子替换、完整undo/redo/旧工具、在途保存关闭及上述继续差异复验。T05 G03保持进行中。

081346_scenes写、081415_scenes读：新增adapter/driver配置核对与保存释放等待后，默认模式再次通过四负例及tick17/24严格配对；文件11935056 bytes，小于32MiB。保存关闭等待已实现，实际在途关闭验证仍未完成。

## v1.59当前补偿配置复验

153717 writer六项PASS；153745独立reader八项中仅七tick继续FAIL。CompensatedCapacity/PackedRuns/CachedCapacity/PrefetchVelocity开启，不含mixed CPU、逐tick回读、材质trace、shape复用或CPU采样。恢复tick17的15当前/历史字段、metadata与像素逐位一致；tick24只有sand和bed_0的四格25525/27334/28096/40900不同，各1ULP，最大5.960464477539063e-8。其余原生字段、metadata、实际参数/SPIR-V及两态PNG像素全部一致。reader的cold_difference.json列原始值，源/配置及索引留证。比例边界修正没有解决此独立问题，严格门仍FAIL。

153932 writer13PASS、153957独立reader15PASS，唯一观察增强是StepReadbacks：保存态额外8备用字段，每个完成tick读回15字段/画面。此组tick17、18–24各完成态与最终24状态及metadata/参数共146份bin逐位一致，reader raw_pair_comparison.json保存逐份复核；画面也一致。恢复负例仍拒绝。它是改变读回负载的诊断，不能用该组PASS替代原低取数失败，也不能据两组关联确认缺barrier或driver浮点原因。

后续应采用shader内记录并于运行结束后取数，减少tick之间新增读回/复制的观察扰动，捕获首个不同阶段的实际输入和结果。当前普通严格继续问题仍在，G4未放行；撤销及重做仍按v1.44取消，本文早期相关待办只是历史。
