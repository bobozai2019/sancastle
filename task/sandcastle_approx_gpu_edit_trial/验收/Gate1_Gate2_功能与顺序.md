# Gate1 / Gate2 功能与顺序

日期：2026-10-12。判定：独立功能闭环通过；性能探索目标另判，不由本报告推定通过。

入口为 tests/experiments/approx_gpu_edit/beach_trial.tscn，固定 Camera3D、静态 UI 与固定信号保存到场景。256×256 二倍细分网格已预烘焙 grid_mesh.res，运行复用，原视觉资源和 80 浪/侵蚀保持消费。独立 profile 同时用于直接启动与探针。碰撞占位的严格边界见 [T00](T00_隔离与冻结.md)：没有创建碰撞 shape，没有初始化碰撞 RD 管线或请求地形高度。不是以禁用 process 替代去碰撞。

主要功能证据：[functional_20261012_023229_222744](../../../test_output/approx_gpu_edit_trial/functional_20261012_023229_222744/result.json)，原始命令、源码/profile hash、stdout/stderr 在同目录。覆盖平行/背向射线、闭开边界、无库存和极小无库存填沙、分数ID、NaN半径、无限坐标、重复ID、过期epoch、越界、64队列上限、暂停中64笔按序消费及真实鼠标输入路径。场景点击/移动提交，释放或拖入UI终止拖动，点击按钮没有地形命令。暂停编辑没有推进 tick，发布后正常模拟继续。边界诊断快照没有负沙、负水或非有限值。

生命周期证据：[lifecycle_20261012_023100_588546](../../../test_output/approx_gpu_edit_trial/lifecycle_20261012_023100_588546/result.json)。32笔在途编辑后复位：排空再重载，新场景库存/高水位/队列清零，epoch从1增加到2，旧epoch请求拒绝，旧对象已释放；复位中再关闭时关闭优先，关闭停止准入并排空已准入编辑，暂停按钮不能重新启动tick。CPU排空只代表提交及发布请求已完成，不冒称 GPU 已完成；资源释放交由同RD有序释放路径。每笔编辑没有 readback 或 physics_frame 等待。

GPU编辑顺序：CPU queued → 同 render thread 每批最多8笔 dispatched → 完整纹理复制后 publication_requested → 主线程解除批量占用 → frame_post_draw_after_publication_request。模拟 tick 与批量互斥；持续输入时每批后优先一个已到期 tick，避免编辑队列饿死模拟。事件持有 generation、ID、CPU单调时间及提交revision。后绘制事件不等于 scanout、真实 GPU 完成或已测逐像素变化。

准入库存按请求量加减，失败不改库存。提交命令规范化 shape/strength/seed；UI独立挖/填量，缺库存或队列满时有提示。砂体实际体积由模板、0.1m单笔限幅、底限和截边决定，不能据库存声称守恒或真实挖取量。

诊断例外：正常模拟 CFL、潮汐和定期沙/水数值审计读回继续保留；固定验证边界读取 GPU 原生字段。准确中间对照保留 GPU 内部 receipt/control，但没有逐笔 CPU receipt 读取或结算授权。其revision是提交序列，诊断前不宣称每笔实际量已确认。
