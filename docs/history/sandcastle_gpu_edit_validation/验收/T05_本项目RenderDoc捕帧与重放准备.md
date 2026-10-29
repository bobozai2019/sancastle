# T05 本项目 RenderDoc 捕帧与重放准备

2026-10-11，Godot4.7.2/D3D12/GTX1050，可见1920×1080、原完整侵蚀/foam/front/80浪计划；RenderDoc1.46。命令tools/run_renderdoc_capture.ps1。仅本项目测试Godot，未访问/重放竞品test1.rdc，也未操作现有editor及RenderDoc实例。

090905_renderdoc：ExecuteAndInject实际创建Godot，但控制脚本错误读取ExecuteResult.status（本机字段是result），捕帧FAIL。测试marker PID12048、tick17；根据该PID及完整命令行核对后，释放测试暂停让该自有目标退出。日志与文件索引保留，早期被锁日志hash未取得，退出后重新索引。

091015_renderdoc：助手PID17924、返回ident38920，目标PID20468与marker完全一致。ready tick17、revision53、process_frame54；释放仍tick17、process_frame56。成功产出frame58–65八份非空RDC（单份约56–69MB），实际size/SHA256见capture_host.json。目标正常断开，原测试完成报告存在且为PASS。该结果是捕帧运行成功，不是cold restore失败配对复现；此轮仅运行写分支。

独立重放助手逐份OpenFile/OpenCapture成功，API属性GraphicsAPI.D3D12。179个compute dispatch分布如下：

| capture frame | actions | compute dispatch |
|---|---:|---:|
| 58 | 60 | 11 |
| 59 | 92 | 33 |
| 60 | 60 | 11 |
| 61 | 104 | 34 |
| 62 | 60 | 11 |
| 63 | 103 | 34 |
| 64 | 60 | 11 |
| 65 | 103 | 34 |

每个dispatch保存该捕帧event、当时shader ResourceId及dispatchDimension。没有据此直接命名为CPL或认定属于某tick。成功重放报告replay_probe.json。重放后八份原始RDC的SHA256均保持，见replay_source_hash_check.json。

首次重放脚本误用CaptureFile.GetDriverName，失败报告随后被同名成功报告覆盖；已从当时完整工具输出补录replay_initial_failure_from_output.json，并明确标明原文件不在。现有工具后续使用replay_probe_pid_<PID>.json与latest指针保留各次结果。replay_tool_index记录的是该命名加固后的当前工具版本，成功运行使用的是命名加固前版本，重放主体相同；不冒称它是执行前原始版本hash。

RDC、日志、marker、JSON及artifact_index均留在本任务evidence目录。下一步实际shader绑定/常量/字段输入和具体子步映射仍未完成；原ULP恢复差异、活动恢复/撤销/重演及T06未完成，G4保持未放行。
