# T05 隔离准备与自有小程序验证

状态：T05-G01已完成、G02进行中，1/4小目标完成。两帧原六核及已映射GPU参数对应齐；三模式pilot有明显尾部／抓帧停顿，前后台状态未采，D07未冻结，G4未通过。

## 实际证据

- [首个helper](../../../docs/competitor/evidence/water_solver_reconstruction/t05_isolation_probe_20261025_v1/manifest.json)：驱动exit1；HKCU私有hive及文件写边界有效，LocalLow匹配失败。初版KnownFolder GUID字节写错，按实际SDK定义修正，旧失败保留。
- [修正后helper](../../../docs/competitor/evidence/water_solver_reconstruction/t05_isolation_probe_20261025_v2/manifest.json)：驱动exit0。四个KnownFolder及三个legacy CSIDL返回规定私有目录；根内写入8 B，根外同前缀兄弟文件写入被NtCreateFile拒绝，Win32错误5。RegCreate／Set／Query成功且读回DWORD 0x57415452；真实HKCU测试键运行前后均不存在，目录外文件也不存在。
- [程序副本](../../../docs/competitor/evidence/water_solver_reconstruction/t05_runtime_copy_20261025_v1/manifest.json)：28个非RDC文件，425466211 B，目标work/runtime_game_v1。原件前后及副本hash一致，源树无symlink／junction；GameAssembly SHA256 `147030ecf9527a25250238120364eb761390b99688b1812c4ea555b3b04e56a0`。没有启动exe或复制用户存档；副本可由原包重建，唯一证据保留于正式run。
- [helper v3](../../../docs/competitor/evidence/water_solver_reconstruction/t05_isolation_probe_20261025_v3/manifest.json)：增加根内／外rename、外部注册表写拒绝与子进程拒绝，驱动exit0。
- [helper v4](../../../docs/competitor/evidence/water_solver_reconstruction/t05_isolation_probe_20261025_v4/manifest.json)：上述检查回归通过，另验证NtCreateFile别名读写映射；真实别名没有文件，私有目标读回redirect八字节。驱动exit0。
- [实际启动及pilot审计](../../../docs/competitor/evidence/water_solver_reconstruction/t05_pilot_audit_20261025_v1/manifest.json)：v6–v10原始文件hash逐项匹配；runtime_setup.json与hook_coverage.json为实际partial产物，不代表G01关闭。

实际使用vendored Frida17.23.3；全局Python未安装frida。源为tools/runtime/isolation_guard.js、isolation_probe.cpp和两个Python驱动。SDK KnownFolders.h的身份、配置、构建命令、stdout/stderr、Frida事件、helper结果和hive均有正式hash。GUID通过UUID.bytes_le转换，实际原生SDK调用验证，不再猜测字节序。

## 范围与剩余工作

通过RegLoadAppKeyW建立独立hive，再用RegOverridePredefKey仅映射自有进程HKCU。Nt registry写边界限制私有hive，NtWriteFile和rename检查实际句柄路径；进程创建拒绝。路径检查拒绝现有reparse祖先，helper不是完整reparse攻击测试。允许非磁盘device／pipe；没有完整OS sandbox、代理进程或全部持久化API证明。

现有capture.py只是备份资料；旧agent以Paint附参数且含无关Readback RVA，没有复用其启动或业务hook。新runtime_startup.py在spawn暂停态先装guard并验证ready，所有停止只针对本次PID。--seed-user-data将现有5个文件29308510 B逐字节复制到私有目录，记录复制前hash，不解析profile／save；原用户资料没有写入。

## 实际启动与失败边界

所有run位于正式evidence/water_solver_reconstruction，前缀t05_startup_20261025_v。

| run | 实际结果与限制 |
|---|---|
| v1 | 约2 s异常退出，没有Player.log；原资料／副本监测一致，失败保留 |
| v2 | 15 s进程存在，但没有引擎日志；旧驱动仅以进程存活记operation complete，不能作为初始化通过。诊断版回调含不适用上下文访问，已移除 |
| v3 | 再次早退；异常通知只定位到KERNELBASE系统异常，未证明唯一根因 |
| v4 | NT句柄路径解析／file position与mode处理补充后进入Unity6000.4.10f1 D3D12；日志显示读取真实LocalLow，隔离不充分。未改原用户文件 |
| v5 | 增加NtCreateFile／NtOpenFile原目录前缀读写映射；实际记录Game.profile映射，空初始数据启动后退出，原因未分析业务逻辑 |
| v6 | opaque资料副本＋新水观察器兼容试跑，20 s；dropped1220、entry缺失，判LOG_DROPPED及调用不闭合 |
| v7 | 参数wrapper层未取到有效参数；事件闭合不等于覆盖完成 |
| v8 | 原生icall取得参数与绑定，但序号／调用缺失；dropped0不能判完整 |
| v9 | 补全局与部分CommandBuffer路径，仍缺一个entry；序号／调用不闭合 |
| v10 | exclusive QPC与先构造时间戳再入队；20.033 s，13919条seq连续、6040对CPU调用、最终inflight／dropped／hook errors均0，前后监测一致；仍为pilot |

不能从v4多项兼容性修正或v6组合变化反推唯一启动根因。原始失败没有覆盖。所有启动都在guard ready后resume；v4读真实资料的缺口并未冒称隔离通过，后续才使用实际边界映射。

## v10窗口及其边界

v10 QPC频率10000000；实际全局waterResolution512×512、16×16×1组，与T03／T04的512×256不同。完整正轮数CPU链455条，其中267条三轮、188条四轮；velocity／height／advection参数dt .00732421875，source dt .02500000037。全局playTime／frameCount已记录，但不是GPU或Present时钟。455条链只是pilot观测，不是D07正式窗口。

CPU entry端点相隔12.9906319 s，所附playTime相差11.3649606705；比值仅为带观察器端点诊断，不冻结为时钟速率。初始化、背景运行、Unity时间限幅、guard及记录扰动尚未区分，不能据此拟合Godot时钟。1338个CommandBuffer提交API事件中无当前水对象匹配记录；数组、间接dispatch、clear／reuse等覆盖尚需闭合，也未做GPU shader hash／CB实际对应。

v8／v9自报0丢样却缺entry，已成为真实负例。旧emit表达式在计算NativeFunction QPC时可能让队列flush重入，发生事件加入旧batch的窗口；修正后v10闭合支持该修复有效，但尚无长窗口保证。每次检查完整序号、统计总数、entry／return和inflight，不能只看dropped字段。

v10尚未包含的RenderDoc、共用Present、命令缓冲生命周期与必要路径哨兵，实际补证见下节。原始v10证据不回写这些后续能力。运行知识归档docs/competitor/水求解参考与同步.md；不调查平台接入或存档业务实现。

## G01实际关闭依据

[冻结回执](../../../docs/competitor/evidence/water_solver_reconstruction/t05_setup_20261025_v1/manifest.json)关联正式runtime_setup.json、hook_coverage.json、全部输入manifest、源码及hash；验证通过，G01关闭。接受版本为observer SHA256 `f5162edae586e10c3ac9fcfb950cc7849538e5a7d0ecee75969bdbc95e13d382`，不是任意未来修改版自动通过。

1. [RenderDoc helper v5](../../../docs/competitor/evidence/water_solver_reconstruction/t05_renderdoc_helper_20261025_v5/manifest.json)实际在Frida spawn暂停态装好guard后调用外部renderdoccmd inject，再检查API、最后resume。注入完成前entry文件不存在，helper main读取guard ready标记且原生／Frida API1.6均返回1；目录／hive／读写映射／外部写及子进程负例回归通过。没有在游戏图形初始化回调中Module.load。工具与DLL／header身份在manifest。
2. helper v1／v2的Frida API调用报system error；v3又因只解析stdout错拒成功ID，均保留。renderdoccmd的38920是target control ID，文本在stderr，不能把非零退出码一概当失败。Frida NativeFunction设置exceptions:propagate后，正常native异常交给目标处理，v5成功；不修改目标异常处理业务逻辑。
3. 当前observer读取原生icall，补Clear／ReleaseBuffer使CommandBuffer记录状态在清理／释放时复位；未解码array／keyword等setter及未建模水命令被哨兵记录，命中后错误而非默默继续。直接DispatchIndirect未见于本包stripped元数据，保持覆盖边界。light v1有4576次clear／release，capture v2有5976次；两窗口未命中未建模水路径。没有水对象CommandBuffer记录不等于所有未来路径不存在。
4. [capture v1](../../../docs/competitor/evidence/water_solver_reconstruction/t05_modes_capture_20261025_v1/manifest.json)和[v2](../../../docs/competitor/evidence/water_solver_reconstruction/t05_modes_capture_20261025_v2/manifest.json)实际得到200605822 B／201718854 B RDC。独立按程序hash扫描，[重放v1](../../../docs/competitor/evidence/water_solver_reconstruction/t05_capture_replay_20261025_v1/manifest.json)和[v2](../../../docs/competitor/evidence/water_solver_reconstruction/t05_capture_replay_20261025_v2/manifest.json)均匹配原六核，一条三轮链，16×16×1组／512×512。
5. [消费对应v1](../../../docs/competitor/evidence/water_solver_reconstruction/t05_consumption_20261025_v1/consumption.json)及[v2](../../../docs/competitor/evidence/water_solver_reconstruction/t05_consumption_20261025_v2/consumption.json)分别以唯一CPU source playTime 8.505648612976074／11.202048301696777关联整条12-dispatch链，顺序／组数及已映射参数全部一致。原GPU字段／CPU值为C3，唯一相位与顺序对应是C2；没有原生指针到D3D ResourceId的直接映射，不能上升为全路径C3。
6. source dt／积分dt／playTime／grid／cell／gravity／advection／wave／customWave等按原始CB分量匹配。`light_factor` GPU两帧均1，CPU设置来源尚未映射；CB125整向量也不等于任何本窗口已记录全局向量，禁止凭值1猜成sunColor或补虚构setter。该未知不改变已观察GPU值，保留到规格。
7. 三模式输入seed及共用guard／Present／host源码hash一致；原资料及副本监测前后一致。G01限定当前包／初态及当前直接水路径，非OS sandbox或全交互路径证明。未来交互命中未建模路径时必须补证／重开相应覆盖；不以G01替代正式扰动或时间验收。

## 三模式pilot与G02未通过原因

[三模式审计](../../../docs/competitor/evidence/water_solver_reconstruction/t05_modes_audit_20261025_v1/comparison.json)的baseline是“不装水记录器”，仍共用进程隔离和最小Present观察器。light v1与capture v2的水记录器hash相同；capture v1版本不同，不纳入此三模式对照。所有序号／调用／最终inflight闭合，均0记录丢样／hook error。真实SwapChain描述960×540、windowed1；所有所选Present sync_interval1、flags0。不是仅依据命令行尺寸推定。

| 模式／run | 实际窗口 | 共用Present对数 | 回顾性8–12 s间隔中位／P95 | 该run最大间隔 |
|---|---:|---:|---:|---:|
| baseline v1 | 25.049 s | 564 | 32.63155／42.094085 ms | 278.9213 ms，初始化 |
| light v1 | 25.090 s | 463 | 34.8981／93.94875 ms | 333.5135 ms，初始化 |
| capture v2 | 35.101 s | 603 | 31.9222／67.91102 ms | 3139.236 ms，随后845.2363 ms |

表中8–12 s以第一条Present entry为零点，是事后pilot诊断，不是D07正式窗口。capture在resume后18 s请求一次后续Present抓帧，最大间隔对应call273、第一Present后14.402055 s的端点；启动到第一Present有时间差，二者不可混成同一零点。

窗口可见／最小化／前后台和输入未逐时采样，且每模式只有一次，OS／背景GPU活动未受控；不能把差异全归因于记录器，也不能用相近中位数忽略尾部。P95从约42 ms到94 ms是必须调查的风险，抓帧3.139 s不能算模拟dt。G02／D07因此未通过；没有固定40Hz结论。

下一步把重复整份参数／绑定／全局快照改为不可变版本引用，保留可重建性、完整序号与CPU return配对；增加所有模式共用的窗口／前后台／有限输入状态采样，再按相同版本做重复对照，冻结判据后才采正式轨迹。新记录器要重验受影响的覆盖和GPU对应，不能继承旧版PASS。

官方依据：[RegLoadAppKey](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regloadappkeya)、[进程内RegOverridePredefKey](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regoverridepredefkey)、[Frida Interceptor](https://frida.re/docs/javascript-api/)。Unity的[persistentDataPath](https://docs.unity.com/en-us/engine/6000.6/script-reference/unityengine/application/persistentdatapath)及[PlayerPrefs](https://docs.unity.cn/2021.1/Documentation/ScriptReference/PlayerPrefs.html)说明默认机制，不能代替本游戏版本的实际写入证据。包内app.info为BubblebirdStudio／Sandcastle，只确定静态身份。

## 已执行命令

`--help`与下列操作均已实际运行；最新helper exit0、pilot驱动exit0。所有自有进程已退出，未终止用户进程。每次run的sources保存当时驱动／guard／observer，manifest保存完整调用、源hash和产物hash；不得用当前脚本hash倒填旧run。

```powershell
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/probe_runtime_isolation.py --output D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t05_isolation_probe_20261025_v1
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/probe_runtime_isolation.py --output D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t05_isolation_probe_20261025_v2
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/prepare_runtime_copy.py --game-output D:/godot/project/sandcastle/task/competitor_water_solver_evidence/work/runtime_game_v1 --output D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t05_runtime_copy_20261025_v1
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/probe_runtime_isolation.py --output D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t05_isolation_probe_20261025_v4
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/runtime_startup.py --output D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t05_startup_20261025_v10 --seconds 20 --seed-user-data --observer D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/runtime/water_observer.js
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/probe_runtime_isolation.py --output D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t05_renderdoc_helper_20261025_v5 --renderdoc-inject
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/runtime_startup.py --output D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t05_modes_baseline_20261025_v1 --seconds 25 --seed-user-data --present
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/runtime_startup.py --output D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t05_modes_light_20261025_v1 --seconds 25 --seed-user-data --present --observer D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/runtime/water_observer.js
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/runtime_startup.py --output D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t05_modes_capture_20261025_v2 --seconds 35 --seed-user-data --present --renderdoc --capture-at 18 --observer D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/runtime/water_observer.js
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/run_replay.py --request D:/godot/project/sandcastle/task/competitor_water_solver_evidence/requests/t05_capture_replay_v2.json --script D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/multicapture_replay.py
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/audit_runtime_consumption.py --runtime D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t05_modes_capture_20261025_v2 --replay D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t05_capture_replay_20261025_v2 --output D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t05_consumption_20261025_v2
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/audit_runtime_modes.py --runs D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t05_modes_baseline_20261025_v1 D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t05_modes_light_20261025_v1 D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t05_modes_capture_20261025_v2 --output D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t05_modes_audit_20261025_v1
python -X utf8 D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/freeze_runtime_setup.py --output D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction/t05_setup_20261025_v1
```


## G02：版本引用、原生标量与D07冻结

本节补充旧三模式pilot之后的实际执行，不回写旧失败。D07已accepted，见[冻结receipt](../../../docs/competitor/evidence/water_solver_reconstruction/t05_d07_freeze_20261025_v1/decision.json)。当前T05为2/4，G4仍未通过。

所有run位于`docs/competitor/evidence/water_solver_reconstruction/`，各自manifest保留实际命令、源码hash、raw和错误。GPU串行执行，own PID由启动器回收。下列参数和Present成本限定当前副本及初态，不是主项目性能或无探针原作频率。

| run | 实际结果与边界 |
|---|---|
| t05_snapshot_pilot_20261025_v1 | schema2，9202对dispatch，72份影子；不再每dispatch重复全部状态 |
| t05_snapshot_validation_20261025_v1 | 72份影子无重建差异，5种实际损坏负例被拒绝 |
| t05_observer2_baseline_20261025_v1／v2 | v1发现client1280；v2记录ResizeBuffers，证明初始960×540随后1280×720。旧仅创建描述不能证明稳态分辨率 |
| t05_observer2_light_20261025_v1 | 旧JS标量30 s，单独运行尾部大，不能隔离所有系统扰动 |
| t05_hook_detach_diagnostic_20261025_v1 | 同进程22 s卸水hook，仍有尾部；仅诊断，不作连续轨迹 |
| t05_hook_abba_diagnostic_20261025_v1 | 同进程16off／26on／46off，四窗均前台；诊断缺口显式标记 |
| t05_observer2_capture_20261025_v1 | JS标量，13019对，clock每17次source；t05_snapshot_validation_20261025_v2核对102份影子；t05_capture_replay_20261025_v3和t05_consumption_20261025_v3核对四轮链121项无差异 |
| t05_clock_native_20261025_v1 | 追加四个公开Time getter实际icall解析，12092对，54次原生时钟样本 |
| t05_clock_audit_20261025_v1 | 前述两run时钟／source关联，983／913次前缀累计积分轮数与floor(N source_dt/integration_dt)对应。固定上下文dt .025、timeScale1，不证明墙钟40Hz |
| t05_scalar_bridge_helper_20261025_v1–v4 | replacement转调原型改变callee入口LastError；失败保留，禁止用于正式记录 |
| t05_scalar_bridge_baseline_20261025_v1 | 无scalar hook的同helper原始行为正确 |
| t05_scalar_bridge_helper_20261025_v5／v6 | CModule onEnter读取XMM，双线程原调用f32／LastError正确；v6另覆盖12个IEEE754检查点，包括±0、NaN payload、±inf |
| t05_scalar_bridge_overflow_20261025_v1 | capacity2使overflow显式增加，原调用仍正确；expected-overflow负例通过。版本早于检查点扩充，不冒充v6完整同源码 |
| t05_native_scalar_pilot_20261025_v1 | 10013对，78份影子，native overflow0、errors0；仅pilot |
| t05_d07_acceptance_20261025_v1／t05_d07_evaluation_20261025_v1 | candidate_v1先于试验登记；JS标量P95增量13.953625 ms超过12.5 ms，失败，未放宽限值 |
| t05_d07_acceptance_20261025_v2／t05_d07_evaluation_20261025_v2 | 原生方案但四窗foreground均false，校准无效；不据该成本判断原生后端 |
| t05_d07_acceptance_20261025_v3／t05_d07_evaluation_20261025_v3 | 同candidate_v2原生配置，Sky激活仅自有窗口；四窗均前台，on444／off451个间隔。中位增量0.0036 ms、P95增量5.888515 ms，限值未改，通过 |
| t05_native_scalar_capture_20261025_v1 | 35 s、自有窗口前台激活、18 s请求单帧；11654对／31191事件，丢样0、错误0、inflight0，native overflow0。抓帧SHA256 2a7e56a76a08e960ee91097b560d8b18732166050a70792c825a25e59139a925 |
| t05_snapshot_validation_20261025_v3 | 原生抓帧91份影子无差异，5损坏负例均拒绝，全部raw身份核验 |
| t05_capture_replay_20261025_v4／t05_consumption_20261025_v4 | 原六DXBC独立匹配，一条四轮链；121项已映射常量／组数相同。light_factor GPU1，CPU来源仍unknown |
| t05_d07_freeze_20261025_v1 | criteria hash、通过校准、helper／overflow、影子与GPU审计关联；当前源码同时等于校准及抓帧保存版本；accepted，仅关闭G02 |

### 可复验命令

通用最小命令（输出必须更换新目录，不能覆写上述run）：

```powershell
python -X utf8 task/competitor_water_solver_evidence/tools/runtime_startup.py --output D:/absolute/new_run --seconds 45 --seed-user-data --present --clock-sample-every 1 --native-scalars --observer D:/godot/project/sandcastle/task/competitor_water_solver_evidence/tools/runtime/water_observer.js
python -X utf8 task/competitor_water_solver_evidence/tools/validate_snapshot_trace.py --run D:/absolute/shadow_run --output D:/absolute/new_validation
python -X utf8 task/competitor_water_solver_evidence/tools/run_replay.py --request task/competitor_water_solver_evidence/requests/t05_capture_replay_v4.json --script task/competitor_water_solver_evidence/tools/multicapture_replay.py
python -X utf8 task/competitor_water_solver_evidence/tools/audit_runtime_consumption.py --runtime D:/absolute/runtime --replay D:/absolute/replay --output D:/absolute/new_audit
```

重放请求v4原样用于定位既有结果，重新运行须新run_id／output_root并保留同一source hash，不能覆盖v4。正式无影子运行不调用要求shadow的验证器；仍需序号、快照引用、调用配对、实际窗口和时钟覆盖核验。

### 生效边界

记录器scope／key／snapshot ID保证前序版本可追溯，重复同值合并后value_since_qpc不再代表最近一次setter。原生f32 bits缓存8192项，溢出即失败。所有诊断卸钩轨迹有缺口，均不能用于求解器／连续时钟参考。capture仅补实际GPU消费，抓帧停顿不能用来估计原作步长。

D07正式45 s、QPC epoch后15–35 s，1280×720 visible／foreground／非最小化，Sync1／flags0；clock每source，shadow0。500 ms窗口／鼠标状态只覆盖采样点。尚缺可验证输入变化的正式轨迹、生命周期与完整时钟消费，G4不通过。T06保持512×256并为新的序列身份先补原DXBC参考；不扩用512×512运行数据或旧数值预算。


## G03部分执行：自然轨迹与前台失败

- t05_formal_natural_20261025_v1／对应audit_v1：45 s、1514次source／clock配对，窗口798次；第25.668秒foreground变false，正式窗口失败。原生clock独立审计在t05_formal_clock_audit_20261025_v1，计数对应无差异，但不因此接受窗口。
- t05_formal_natural_20261025_v2／audit_v2：采样时不再启动其他命令，1462次配对、窗口800次；第25.251秒失前台，仍失败。失焦原因未知，不能归因于某一外部程序。
- t05_formal_natural_20261025_v3／audit_v3：增加中途再激活计划，1447次配对、窗口800次，仍失败。第一次Sky操作UTC 11:59:13.433–11:59:22.453；后续刷新窗口时自有进程已自然结束，未对任何其他窗口操作。
- t05_formal_natural_20261025_v4／audit_v4：同一次Sky调用每8秒刷新／激活自有窗口，1456次配对、窗口800次；前台仅从20.17秒起稳定，未覆盖预先固定的15秒起点，仍失败。没有挪动窗口以追认通过。
- [t05_formal_natural_20261025_v5](../../../docs/competitor/evidence/water_solver_reconstruction/t05_formal_natural_20261025_v5/manifest.json)／[audit_v5](../../../docs/competitor/evidence/water_solver_reconstruction/t05_formal_natural_audit_20261025_v5/trajectory.json)：首20秒每2秒、之后每8秒通过Sky刷新并激活唯一已识别自有窗口，不发送鼠标／键盘。原45 s／15–35 s窗口不改。40份窗口状态、796次窗口source、1466次全程source／clock逐次配对，序号、快照、调用返回、native cache和raw身份闭合，配置源码等于D07冻结版本，正式无主动水输入／自然参数推进这一条件通过。

[UI操作原始receipt](../../../docs/competitor/evidence/water_solver_reconstruction/t05_formal_actions_20261025_v1/manifest.json)保存v4／v5操作时间；只有前台激活，不是受控水输入。500 ms状态采样不证明采样间完全无输入，静置指无主动编辑，不代表水场物理静止。v5的[原生时钟审计](../../../docs/competitor/evidence/water_solver_reconstruction/t05_formal_clock_audit_20261025_v2/manifest.json)记录1466次，fixed context／dt .025／scale1一致；累计轮数对应仍无差异。

另一次t05_input_ui_probe_20261025_v1以相同guard运行60 s，仅请求自有窗口Sky截图／可访问性；截图超时，无画面，不猜坐标、不试键。只记录能力缺口，没有可控输入证据。自有PID全部退出、原用户资料／源副本hash未变，GPU已释放。

G03仍进行中，不改总体22/32或G4状态。下一项为公开引擎Time.timeScale受控变速小样本：先验证实际icall与调用线程，再预登记控制动作／相位及与D07配置的兼容性；这是引擎实验干预，不得描述为原作UI操作、波形控制或原作业务实现。若影响观察器源码／生效配置，先版本化重验受影响校准，不能沿用旧receipt伪装覆盖。


## 公开Time控制补证与G4收口

以下为后续实际执行，旧“G03未闭合”段落保留为过程状态；最终判断以[G4](G4_20261025.md)及t05_clock_mapping_20261025_v1为准。

| run | 实际结果 |
|---|---|
| t05_clock_control_pilot_20261025_v1 | 公共Time setter实际registry解析，12秒.5立即读回，但仅一个source clock保持.5；20秒恢复时old已1，单脉冲不能持久；操作成功但持续变速假设不成立 |
| t05_clock_control_pilot_20261025_v2／audit_v2 | 显式hold，监听后续公开setter读回1并重申.5共265次；半速160个原始source clock，核心phase120个；3种控制损坏负例拒绝 |
| t05_control_clock_audit_20261025_v1 | 两pilot原生时钟／dt／累计轮数核对，无差异；v1不当持值通过 |
| t05_control_calibration_scale1_20261025_v1及eval | 新driver／sidecar，空动作，B-A-A-B；中位／P95增量.2383／7.2503 ms，通过先定界限 |
| t05_control_calibration_scalehalf_20261025_v1及eval | 10秒持.5、56秒恢复；预定四校准窗scale均.5，中位／P95增量.02625／9.96042 ms，通过；诊断卸钩区间不作连续轨迹 |
| t05_control_sidecar_audit_scale1／scalehalf_20261025_v1 | 原控制seq、动作／读回、raw hash闭合；诊断gap明确，恢复后water未开hook无clock不伪造补点 |
| t05_control_capture_20261025_v1及capture_audit | 35秒，12–25秒持.5，18秒抓帧；RDC SHA256 b9808c58cdf1251d9f3c422bae7c1c289c2c589e13ec708fffaeb7d5070fff0b |
| t05_capture_replay_20261025_v5／t05_consumption_20261025_v5 | 原六程序独立重定位，三轮链；95项已映射CPU／GPU常量和组数一致；被配对source原生scale=.5 |
| t05_d07_control_freeze_20261025_v1 | 两scale校准、sidecar、原ABI／schema、半速GPU消费与所有实际源码hash关联，配置冻结；旧D07仍是自然轨迹版本 |
| t05_control_formal_20261025_v1 | 45秒无抓帧，20秒.5／30秒恢复1，hold重申358次；window_audit通过40份状态／600次窗口source；phase_audit3负例拒绝；clock_audit1305次source／clock，累计轮数差0 |
| t05_clock_mapping_20261025_v1 | 重新核验自然／受控原始身份、两D07、两正式窗口、每source clock、GPU消费及phase，所选条件G4 passed；GPU运行时间保持null |

新driver在runtime_control_startup.py，不修改D07原host；新sidecar在runtime/clock_control.js。公共setter真实调用在已识别源汇Dispatch返回线程，要求native inFixedTimeStep成立；只改公开engine输入，未读写任何游戏业务方法。快照读取完整覆盖之后才用实际call_id／QPC作动作对应；sidecar较早安装可能先观察到水调用，不将其source_returns强行等同主observer计数。

所有自有PID已退出、GPU释放，原用户资料／源副本hash未变。当前24/32小目标、6/8任务，G0–G4共5/7门通过。T06／T07仍须完成。
