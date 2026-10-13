# ADR v1.34：完整沙滩双物理槽GPU前态

2026-10-11，仅候选存储原语；未默认接入编辑、公开撤销/重做或重演。

观察本项目sand_commit和water_commit的实际绑定与写入：沙编辑写两张sand，水事务将water/sediment/qx/qz写两物理槽。完整场景当前与备用水/动量/悬沙可能不同；实际E事务改写备用层已验。因此不能把numeric单份当前字段复制回两槽，宣称完整原生历史恢复相等。

`beach_gpu_edit_history.gd` 保存五字段各两张R32纹理，当前index、revision、solver实例、generation、完成tick和64位命令身份。仅render thread操作；receipt/publication在途或pending capture时拒绝。finish(applied)控制保留/丢弃，失败pending释放；只匹配同solver实例、generation/tick才允许原语恢复。发布、账本、prefix、碰撞、代际与redo由尚待实现的协调器负责。

完整纯GPU堆挖没有写wetness/compaction/rock/obstacle/flux和foam/bed/front。其同tick无需为这些未改字段另分配前态；当前实测E前态恢复后完整23字段相等支持这一适用范围。跨tick及旧CPU混合工具不得使用该快路径；仍需完整检查点重演。

完整原语最多32笔，256²每笔40N=2.5 MiB，保留80 MiB、暂存第33笔峰82.5 MiB，新分配前上限96 MiB。淘汰最旧记录，release必须早于owner solver释放。数值原语v1.15仍保持1.5 MiB/笔、48 MiB/32笔和64 MiB上限，未改变其预算。完整候选独立预算增加来自必须保留两物理槽；不把两者的逻辑payload视为驱动实际内存，也不把原语功能通过当作成本通过，T06需测新增复制与内存。
