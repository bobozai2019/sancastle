# T05 完整原分支重演与首差异tick

2026-10-11，Godot4.7.2/D3D12/GTX1050，1920×1080活动完整沙滩；worker独立SubViewport/world，不作成本证据。

`20261011_102953_beach_replay_original_probe` 五项中四项通过、严格原分支FAIL。tick0完整初始化锚点先于开放输入；tick15实际E挖0.01m³，tick16实际C放0.005m³，推进tick19。在隔离worker从0重演同记录，关键回执匹配、shader materials分离、活动authority/像素保持、worker实际关闭通过；严格完成态不同，未提交任何目标分支。

原始before/replayed.scp均保留。离线 `beach_checkpoint_diff_export.gd` 使用原Store读取并分别导出23原始字段，索引记录源文件SHA256及各bin大小/hash。首次导出因filename类型推断失败，日志另存export_parse_failure.log；修正后成功。该派生导出不覆盖原检查点，也不根据当前源码重建旧数据。

两个检查点tick19/revision59/current_index1/foam_index1相同，五账本与prefix相同。沙六格差异最大1.1920928955078125e−7，索引25014/25267/25271/26825/27064/27065；差异已传播到水/动量/悬沙/flux和foam/bed/front。具体数量、值和证据定位以checkpoint_diff_exports.json及原bin为准。不能仅凭小幅度放宽严格标准。

单因素诊断 `20261011_103811_beach_replay_original_probe` 使用--beach-copy-sand-trace，仍严格FAIL，其他四项通过。两条时间线tick1–7沙字段逐位相同；tick8第一次不同，索引27322：active0.7136970162391663，worker0.7136969566345215，差5.960464477539063e−8。tick10/11各四格差异，tick19两格差异。十九个完成tick的两份R32原始bin分别保留，未用无时间依据的帧号换算秒数。

观察事实C3仅限诊断完成tick边界：差异早于tick15第一笔编辑，不由该笔事务直接触发。它没有证明tick7的其他22字段相同，也没有定位tick8具体水/沉积/材质pass，更没有确认与旧四格ULP相同根因。复制改变GPU调度，因此不冒称默认版本首差异也是tick8。

当前完整跨tick恢复仍不能验收。下一步核对第一差异附近完整输入、实际参数/绑定及相关pass；失败与当前状态保留，G4不放行，T06未完成。

复验：`tools/run_beach_recovery_probe.ps1 -Probe beach_replay_original_probe`，诊断另加-SandCopyTrace。源hash、工具、binary、编译/运行命令与实际PID、独立报告及产物索引分别保存。
