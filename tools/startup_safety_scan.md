# 启动与资源安全扫描

`startup_safety_scan.py`检查项目中的场景/资源初始化风险，并调用同版本Godot验证实际加载与实例化。输出目录必须在项目内且不存在；不会修改运行源码或用户启动配置。TEMP、TMP、APPDATA、LOCALAPPDATA和缓存均重定向至输出目录。原用户启动配置只读复制到该目录。

输出目录写入.gdignore；位于test_output时也确保该目录的隔离标志存在，防止带相同UID或class_name的测试副本进入编辑器资源索引。手动清空临时目录后，下一次运行会恢复此标志。

```powershell
# 加载assets中的tres、scenes中的tscn，场景各实例化两次但不入树。
python tools/startup_safety_scan.py --output test_output/startup_scan_全新编号

# 只检查源码模式，不启动Godot。
python tools/startup_safety_scan.py --output test_output/startup_static_全新编号 --static-only

# 另外实际启动main与test1_geometry，各推进至少10tick并关闭，重复两次。
python tools/startup_safety_scan.py --output test_output/startup_scan_全新编号 --live

# 将正式入口短运行与全量资源加载分开，便于定位原生崩溃或上下文依赖。
python tools/startup_safety_scan.py --output test_output/startup_live_全新编号 --live-only
```

| 规则 | 检查内容 | 判读 |
|---|---|---|
| R001 | 已分配实例的MultiMesh启用resource_local_to_scene | 通用复制可能先恢复实例数，再设置格式；需实际构造复现，不对所有资源一律取消局部复制 |
| R002 | 场景/资源文本先声明非零instance_count，后声明格式标志 | 可疑序列化顺序；格式必须在分配实例前确定 |
| R003 | 同一函数内先设置可能非零的实例数，再设置格式标志 | 需要结合分支人工核对，不等于完整控制流证明 |
| R004 | 直接对multimesh调用通用duplicate | 核对原生属性复制顺序；显式新建资源时应先设格式，再分配实例 |
| W001 | 函数参数hash覆盖全局hash() | 重名警告候选，不视作启动错误 |
| W002 | 常见Control/Node3D继承链中的局部material或position | 与继承属性重名的候选，需结合编辑器警告确认 |
| 动态日志 | ERROR、SCRIPT ERROR、WARNING、CrashHandlerException及非零退出/超时 | 关联最近的资源或正式入口标记，保留原始日志；不能把原生崩溃归为最后一个场景的脚本错误 |

核心模式是“静态风险 → 实际资源构造 → 入树短运行 → 重进与关闭”。场景未入树的批量构造适合抓复制和依赖问题，不能证明_ready、GPU模拟、信号连接或关闭阶段正确；后者由正式入口短运行提供有限覆盖。没有做输入穷举、长期稳定性或性能验收。

格式限制针对instance_count，不是visible_instance_count；把可见数量设为0不能代替释放实例布局。反过来，局部资源标志只代表潜在复制路径，不能仅凭该标志认定资源已经报错。

`report.json`区分运行失败、待审查的静态风险和警告候选。任何运行错误、原生崩溃、超时或静态高风险都会使最终状态不通过；黄色重名候选单列，不通过禁用警告来掩盖。脚本是有边界的启发式检查，不承诺检出任意跨函数设置、间接属性调用或所有继承类属性重名。

若runtime_pass=true但review_required=true，表示受测运行没有失败，仍有模式匹配需要人工核对；总pass保持保守状态。应保留实际复现或安全复核证据，不能为了得到退出码0批量取消局部资源设置。
