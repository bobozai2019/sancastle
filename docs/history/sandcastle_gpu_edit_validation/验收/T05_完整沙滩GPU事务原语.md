# T05 完整沙滩 GPU 事务原语

2026-10-11。Godot4.7.2/D3D12/GTX1050，可见1920×1080，VSync关闭。每个evidence目录含源hash/资源hash、日志、当前权威字段bin、发布纹理bin、碰撞bin、PNG和artifact_index。无正式性能PASS。

075134_scenes：首轮API事务与编辑后步进成立，四个碰撞断言FAIL。测试使用GDScript float64的rock+sand与GPU R32高度比较，完整沙滩非零rock触发表示差异；原独立fixture的rock=0掩盖了这一测试问题。失败原样保留。

075231_scenes：只修正测试oracle，将权威rock+sand按R32格式编码后与shape.map_data字节比较，不放宽容差、不改碰撞shader。四策略、四组后续两tick、完整负载与不完整prefix保存拒绝共十项PASS。每块记录未舍入float64差和float32字节判定，保存原生碰撞数据供复验。

075334_scenes：不启用FastFullWet的默认路径，共十三项PASS。tick15/17/19/21执行B/C/D/E各一筆自然湿沙附近的原生编辑，实际量严格结算，四张沙/水/qx/qz发布纹理与当前字段逐位一致，dirty及相邻块的33×33原生高度字节完全一致；每笔之后继续原耦合两tick，完成tick23并保持侵蚀、foam/front和80浪计划。

额外负例：非法speed=1.1不消费ID；真实GPU活动时拒绝新API、保存和tick启动。最终第五笔E事务实际receipt_pending时启动shutdown，等实际status1回执、库存结算、发布及碰撞完成才释放。记录receipt_callback_us=11174569，release_us=11795234；solver与collision rd均null，gpu_prefix五笔，关闭没有遗失已确认操作。

证据C3仅限这些固定输入、配置和完成态窗口；不代表80浪全部执行、100ms真实鼠标反馈、三机位长稳或T06成本。当前入口尚未接真实GPU UI队列、GPU编辑后的完整保存/撤销/重演；T05 G01/G03保持进行中。
