# 五工具交互与只读预览阶段

日期：2026-10-14。T07进行中，G7尚未完整通过；正式main/两个继承场景和水下/混合前缀整合留T08。

可操作入口：`res://scenes/shape_brushes/brush_playable_candidate.tscn`，直接启动命令 `godot.exe --path D:/godot/project/sandcastle res://scenes/shape_brushes/brush_playable_candidate.tscn`。运行入口不引用task/test_output；验证用dry-flat子场景仅在tests。正式main入口保持原配置，候选默认暂停，可用空格继续。

五工具面板、11个参数控件、固定信号、两种预览mesh及材质保存到tscn。普通挖填沿用旧amount；城堡点击一次、长按/移动不复制；墙/铲子按距离采样，松开drain。GUI/非法hit中断子路径；右键/Esc/失焦/切工具丢未提交缓存，已提交走原事务终结。UI记录待提交/已提交层次，失败显示中文原因和保持原状，不把GPU错误号当用户提示。

城堡ghost消费同一65² RGBAF模板，实际图像字节与原rgba32f精确一致；H双线性、mask最近邻，node负yaw匹配GPU矩阵，[ / ]各15°且保留Q/E相机。尺寸通过真实SpinBox箭头改变并驱动ghost。局部readonly compute用4RID/64byte、单在途、80ms最短间隔查询foundation base/min/obstacle/water；generation/revision/参数/位置key过期显示等待，点击仍从权威态核对。恢复候选先构建预览资源，失败释放且旧查询器/27场不变，成功换代后再使用新RIDs。

墙预览读取完成床面或当前笔baseline及同截面；铲子显示可见床面上的抛物线cut mask和两侧receiver/方向，未分配的肩量不伪装为已堆高。无方向只显示范围。候选隐藏旧性能面板并禁用其process，避免遮挡；没有开展性能轮次。

## 实际证据

- `tests/shape_brushes/run_shape_brushes.ps1 -Group ui`：`D:/godot/project/sandcastle/test_output/shape_brushes/20261014_090133_ui_9abda89b/`，58项PASS，stderr无错误。Godot v4.7.beta.custom_build.dff2b9bb6、D3D12 12_0/Forward+、GTX1050，seed101/tick0暂停，1280×720及1024×768窗口。
- Input.parse_input_event经GUI/unhandled/physics ray路径，未调用submit来代替用户操作。验证五工具选择、城堡只一次、墙/铲子实际落沙/搬运、普通挖填、键盘旋转/真实尺寸控件、预览原态不变、模板字节、native旧前缀保存/候选失败/恢复换代、GUI松开、stationary/Esc/右键/失焦、实际候选失败中文提示/27raw原态及窗口缩放后按钮仍可操作。
- ui_evidence.json保存实际命令/terminal、source_signature/effective_compilation、查询次数；27纹理前后raw、磁盘ui_before_shape.scp、castle_preview/ui_tools/shovel_drag_ready/ui_1024x768等PNG及manifest/index保留。已查看面板无重叠及两种窗口截图。
- `-Group input`：`20261014_085921_input_86b755f7`61项PASS；其中2m直线的batched/逐事件提交均为相同16个0.125m段，take_count=1，独立端点参考核对，避免shovel合并时机影响预算/分配。旧41项仍通过。

## 阶段失败保留

初版`082741_ui_1f425e4b`13项功能PASS但截图发现与旧性能面板重叠；候选已隐藏该面板。`083752_ui_03ab758c`FAIL：继承场景覆盖Sampling.button_pressed时在未入树阶段触发旧信号，get_viewport为空；已移除该属性覆盖，不修改共享performance脚本。`083921_ui_228830f8`只剩缩放测试FAIL：注入坐标未应用stretch。实际引擎1024×768对应logical viewport1280×960、stretch0.8（独立ui_viewport_inspection确认）；测试现在从logical点经真实stretch变换注入像素。`084315_ui_2fd6a15f`50项PASS。`084856_ui_fa7893a7`尺寸ghost断言在process_frame信号后、节点_process前读取，等待frame_post_draw后精确核对；未放宽比例要求。`085320_ui_84545d1b`57项PASS，最终58项加方向就绪截图；旧结果不改写。

## 当前范围与剩余

T08后续更新：候选已启用edit v4/native v2，混合操作后的两种保存入口及工具/完整参数恢复已验证；见[v4阶段](G8_混合前缀与保存恢复阶段.md)。下方“前缀仍拒绝”是本UI阶段当时的限制，现由该阶段接线解除，水下/正式三入口仍待接。

G01静态面板/参数/信号、G02城堡ghost/yaw/size、G03墙/沟范围/方向预览完成。G04/G05已有上述证据，但完整非法区离开再回来、数字焦点/相机按键、切工具时有在途、暂停/继续等矩阵仍待补齐，不提前判全Gate通过。GUI快慢输入的完整几何对照及burst/碰撞落后负例随最终输入/整合回归完成。schema2新前缀保存目前仍明确拒绝；水下形状工具尚未放行；母任务仍暂停。性能0/3轮。
# 补充：输入与正式布局功能矩阵（2026-10-14）

`102817_ui_matrix_4136ee6d` 21项PASS：真实数字鼠标焦点阻止WASD/QE移动和城堡旋转；实际在途命令的释放后排空阶段切换工具清除未入队尾段，已入队命令只结算一次；真实碰撞readback延迟期间操作等待且不允许新输入，恢复交付后拾取高度更新；真实无命中再落点不桥接路径；暂停/继续结束笔画。`101954_input_8f9a3ea1` 61项采样器/权限回归PASS，包含缓冲上限和不同采样频率路径。

修补：取消规则扩大到draining状态；正常释放只排空一次，取消清除尚未入队段，保留已入队所有权。`101941_ui_matrix_438c703b` 15项PASS先验证此修补；后续增加真实碰撞延迟矩阵。

`103250_formal_layout_6999309d` 21项PASS：实际main本体，1280×720/1024×768、五种工具的三面板均在可见矩形内且互不相交。已查看两张截图，控件、说明与状态可读。静态性能面板移至下方中列，说明显式分行；性能采样逻辑保持，截图内HUD数值不作为成本验收，性能0/3轮。

失败保留：`101719_ui_matrix_8cc71d05` 选错“无命中”点，实际ray命中沙场；`102559_ui_matrix_4eb5a7bd` 探针先等操作终结再释放碰撞，构成自身等待环；`103028_formal_layout_66ae570f` 性能面板最小高度420px导致右列重叠，后改静态中列布局。均未改旧结果。T07五项功能完成；最终G7放行仍需G4/G6相关最终复验。

