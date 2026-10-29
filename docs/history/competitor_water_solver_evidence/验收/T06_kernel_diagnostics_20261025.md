# T06-G02：指令精确导出与原位比较诊断

角色verification_evidence。执行中，G02未通过。整体保持25/32，G5未通过；不将编译成功／少数fixture通过当六核验收。

## 精确来源及候选

`t06_exact_programs_20261025_v1`通过Windows SDK实际D3D_DISASM_PRINT_HEX_LITERALS=0x80和instruction numbering=0x4导出六份冻结原DXBC（97／163／125／100／131／93指令）。source manifest关联原program hash，实际d3dcompiler_47.dll／SDK header／Python及派生asm完整索引。不是原HLSL。默认十进制文本的舍入literal不作为新核常量。

`lower_dxbc_glsl.py`仅支持实际出现的直线指令子集，寄存器以uint4保留bits、源／目的mask按DXBC位置、cb保留原始uint4，显式exp2、sincos、structured byte offset及纹理通道。未知指令／寻址拒绝。`t06_lowering_static_audit_20261025_v2`六程序活跃寄存器分量读取均有前序定义，次数195／357／236／218／244／177；未定义索引、舍入立即数、stride改变和未知opcode四负例均拒绝。v1因负例literal格式触发TypeError而中断，failure.json及原工具保留；未伪报通过。

独立kernel_probe.gd／kernel_probe.tscn固化静态场景，运行时仅创建GPU资源，验证输入／CB／SRV hash、GPU完整前态、local submit＋sync完成后读回，恢复每次完整输入；没有把CPU录制或信号当GPU完成。仍只操作预登记独立项目，不接main／权威水沙。

## 已执行候选比较（旧预算不改）

| run | 单变量及结果 |
|---|---|
| t06_glsl_lowering_20261025_v1 | 精确bits转换、MAD=fma、dot分开，初版水／结构缓冲按flat u32寻址 |
| t06_kernel_pilot_20261025_v1 | CRLF使compute标记未剥离，编译失败，0项数值比较；旧结果保留 |
| t06_kernel_pilot_20261025_v2 | 读取时统一换行，其余同候选；6真实fixture×3。床高／源汇／法线通过，速度／水量／平流共9项失败 |
| t06_glsl_lowering_20261025_v2／kernel_pilot_v3 | 恢复真实stride16 uvec4声明及整元素store，浮点模型不变；三动态核仍失败。水量差异分布变化证明存取形状会影响结果，不能据此单独确定因果 |
| t06_uniform_diagnostic_20261025_v1 | 同uint4候选，静水／均匀流12组×1；静水六核全部通过，均匀流仅速度／水量失败 |
| t06_d3d12_diagnostic_20261025_v1 | 仅Godot rendering-driver改d3d12；同shader和输入，六组5失败，法线通过。床高出现5777格床码差1，不能把所有差异统称原位噪声 |
| t06_glsl_lowering_20261025_v3／separate_mad_diagnostic_v1 | Vulkan、仅MAD由fma改分开乘加；六组全失败。原MAD融合行为是交叉支持推断，未宣称唯一机器指令恢复 |
| t06_glsl_lowering_20261025_v4 | 恢复stride16／MAD=fma／dot分开，并纳入活跃lane静态验证；shader字节与v2完全相同，尚未用补充预算比较 |

所有具体参考身份、逐字段／逐坐标误差、GPU前态、shader源码、实际命令／版本／退出码见各run manifest／kernel_audit。旧失败不回写。

## 原程序自身反证

`t06_native_holdout_20261025_v1`在查看新参考界限前固定三动态原核各8次，保持原exe／原DXBC／原输入／CB、16×8组和32×32线程；24份合法原输出全部被旧v1规则拒绝。`t06_native_holdout_audit_20261025_v1`另核原exe hash与T03冻结版本、各请求依赖、逐次GPU前态hash和真正fence完成、对应旧预算拒绝，24项反证成立。此audit passed只表示反证可信，不表示数值验收或Godot通过。

因此旧v1是有限采样包络，不能拿它的拒绝单独断言Godot错误。也不能把Godot差异直接加入允许范围。旧预算、原G3及全部失败保留。

## 固定补充原参考矩阵

`t06_native_matrix_20261025_v1`在执行前登记全部72个已有program／input／constant／ordered SRV hash身份，copy-on与copy-off各固定16次，共144个原程序进程／2304输出。原exe／源码／DXBC未改。copy-on逐次核原水和全部SRV GPU前态，所有输出核fence实际完成；copy-off明确无同次GPU前态copy，不伪造配对证据。144组operation complete、数据校验passed，绝非Godot通过。

D06-v2当前构建只读旧原数据加该固定矩阵；extra FP／quantization仍0。规则仍为逐格原样本范围＋MAE/P99/max＋逐格离散集合，没有按Godot坐标调限值。字节相同输出仅在内存解码时去重，不影响min/max、集合及全对最大误差，所有原始重复与hash仍保留。旧synthetic来源role过宽的wet_dry描述在v2来源选择元数据修正为按local_reference_id解释，原文件／旧失败不改。

新完整候选在budget v2构造前另登记`t06_full_candidate_v1.json`，明确Vulkan／uint4原位逻辑／32×32／MAD=fma／dot分开／每身份3次，且六shader hash与补参考前v2相同。待新参考规则冻结及核验后，才比较完整72身份。不得用其结果再次无依据放宽。


## v2经验范围与完整候选结果

`t06_error_budget_20261025_v2`已封存72身份、2538原始样本（873个不同输出字节流），文件SHA256 dfcd76345901480fca6dff264a10b57e564a3914c632b67a3be2bc7cc1e4cd31；extra FP／quantization均0。`t06_error_budget_check_20261025_v2`对全部原文件核hash，字节相同者仅复用相同身份下的比较；2538项源数据回归、7种负例均通过，仍不等于预测或移植通过。

`t06_native_holdout_eval_20261025_v2`对没有加入构造的原24份输出重比，仍24/24超界；新范围没有解决独立原程序的逐格预测。停止继续扩样直到通过，不将这些holdout再加入界限寻求绿灯。v2只作为经验诊断资料，不升级为跨后端原位验收依据。

`t06_kernel_full_diagnostic_20261025_v1`按预登记Vulkan／stride16／fma／32×32候选覆盖72×3=216次。158满足经验规则、58未满足；床高和源汇各36/36满足，速度16、水量21、平流15、法线6次不满足。法线未满足出现在原参考也曾变化的夹具，尚未据此证实全部差异原因。每次完整GPU前态、CB、SRV／纹理hash、compiled SPIR-V、后态、源码、命令／版本和逐格差异保存；G02／G5不关闭。

## 后续疑点 Q-T06-NATIVE-ENVELOPE-01

固定输入／seed／stage／原32×32及候选profile均已冻结。候选解释：E1算术／掩码转换错误；E2资源访问形状或编译器浮点改变；E3原位读写的非唯一可见顺序；E4输入／绑定不一致。GPU完整前态／CB／SRV逐次hash排查当前已映射E4，跨后端和分开MAD反例说明不能全归E3。下一项是直接固定实际消费的读取值并分开验证算术与顺序；仅增加输出样本不能解决配对。

拟先建设明确标识的只读快照／读取流适配参考，保持原算术token不变，仅定向改变读取来源；依契约改写后不得称未修改原DXBC执行。其本身需要小样本、负例、输入配对及因果范围核验，再冻结新的正式判据；仅适配程序或CPU自洽通过不能闭G5。原位和双缓冲继续分列，不缩小六核、完整字段、短序列、生命周期和T07范围。

## 显式适配容器小样本

- t06_dxbc_rebuild_probe_20261025_v1：D3DSetBlobPart可处理原有效容器，但清空checksum后的容器以及重复MOV未重算容器被E_FAIL拒绝；失败保留，没有绕过验证或强改版本。
- t06_container_hash_helper_20261025_v1：固定Microsoft DirectXShaderCompiler commit1527671533a955c40a7e43a68f767fde734c4cb5的公开DxilHash.cpp及LICENSE.TXT，源码未改；MSVC19.51.36260.0编译薄包装，六个原DXBC的stored digest全部复算相同。只证明容器checksum实现，不是数学或GPU验证。
- t06_dxbc_rebuild_probe_20261025_v2：按已验证公开函数重算容器checksum，原元数据变体／仅重封装／复制幂等mov三份派生容器均被SDK接受、shader代码按预期保留，97／97／98条指令。复制的是原第93条`mov r1.z,l(0x00000000)`，是寄存器赋值，不是空方法占位。
- t06_dxbc_rebuild_gpu_20261025_v1：三派生容器各3次真实D3D12 floor管线执行成功，原水／sand GPU前态、fence及完整输出hash符合固定床高控制。只证明这组容器编辑与幂等控制兼容性，不证明读取重放、六核等价或G02通过。

新程序全部以adapted／derived标识，原DXBC副本及原RDC保持不变；hash／公开源码、许可证、构建日志、原／派生字节、反汇编及真正GPU输出都在对应正式run目录。当前所有自有GPU进程均已退出。

## D10只读快照与浮点定位（继续执行，未关闭G02）

`t06_snapshot_dxbc_20261025_v1`把原六核u0读取分别1／5／5／5／1／5条改到独立t2，原709条指令的算术token、原CB及辅助依赖保留，独立parent／adapted hash与完整asm在adaptation.json。新增声明和读取来源明确是适配，不能称原程序或已证合法原位调度。

`t06_snapshot_executor_build_20261025_v1`与v2均构建成功，源码相同；期间对转义的复核没有形成实际GPU失败，不编造该失败。`t06_snapshot_reference_pilot_20261025_v1`六参考×3逐位稳定；实际GPU水seed／t2／原SRV前态与fence核验，速度核A5输出seed控制不影响结果，零snapshot改变结果；缺snapshot、短snapshot、原未改向program实际拒绝。`t06_snapshot_rules_pilot_20261025_v1`先于Godot对比冻结严格完整uint4零额外允差，仅适配算术诊断，不替代原位C03。

| Godot run | 唯一模型变化（其余fma／precise／直接除法） | floor／velocity／water／advection／source／normal 不同word数（每次相同） |
|---|---|---|
| snapshot_godot_pilot v1 | 基线；snapshot_glsl v2 | 0／40／0／2／0／0 |
| v2 | 除法写为倒数再乘；glsl v3 | 0／40／0／2／0／0 |
| v3 | 取消precise允许重排；glsl v4 | 0／1860／0／2／0／0 |
| v4 | 所有MAD分开；glsl v5 | 5841／38801／1096／147495／214／58 |
| v5 | 仅e1500第16条MAD分开；glsl v6 | 0／40／0／3／0／0 |

每run六身份各3次完整比较，均operation complete且未满足精确整体规则；不得把导出成功、某四核一致或局部旧偏差消失当G02通过。v1速度vx28格、vz12格均最大1code；平流同一(328,94)的vx最大2code、vz1code。v5消除该点，却在(469,80)及(372,215)引入3个word新偏差。当前项目snapshot shader已用glsl v7恢复到v2基线，六hash相同；原inplace shader不变。精确规则、原数据和所有失败保留。

### 保留正常输出的寄存器观测

工具register_trace.py保留原snapshot全部算术token和u0正常store，增加线性索引、零初始化capture、已定义lane的MOV及独立u1 store；Godot同位置保存到binding5，GPU资源分别恢复／释放。build_trace_reference.py扩展两UAV描述符与独立debug copy／readback，保留真实GPU前态与fence。run_register_trace.py将native及Godot正常输出各自与未观测基线核对，只有相同才解释trace；所有运行各3次稳定。不把正常输出不变当优化过程完全不变的证明。

- 平流i70 r0：3个浮点word不同，均(328,94)，两端正常输出不变。
- 平流i19 r0：1个不同；i9 r0：0；i16 r0：1；i15 r0及r2分别0。
- 平流joint：同一invocation保存i15 r0.y／r2.z到x／y，i16 r0.y到z，i19 r0.y到w。全部两输入相同，仅(328,94)输出1 ULP不同：0x3f244662／0x3f244663，后续fraction为0x3d4c4000／0x3d4c6000。正常输出与未观测基线相同。
- 速度i139 r0：xy分别138／121格不同，zw0；i121 r0：xy各35格不同。joint保存119分子、120分母、121商、139选择后的x速度，差异35／0／35／138；(248,0)分子已经不同，不能归咎除法或打包。

`t06_register_models_20261025_v1`使用joint实际输入检验CPU假设而不充当oracle：平流原生MAD在131072格中1格不等于ucrtbase.fmaf、3格不等于分开f32乘加，没有格同时不等于两者；速度原生第121条对同调用输入，与正确舍入除法47052格不同，与先f32倒数再乘0不同。只解释有限观察；不以此宣称每个MAD选择规则、编译器内部路径或所有div已恢复。原709条opcode非零控制仅sat对应0x2000，无额外隐藏标志线索；Microsoft公开浮点／MAD规范链接存于models.json。

原生trace执行器真实拒绝单UAV未观测布局和缺snapshot两个负例。首次`register_pair_e1500_i70_v1`包装器漏建输出目录，Godot报OUTPUT_DIRECTORY_REQUIRED，在创建shader／dispatch前退出；native已执行，整体不算数值结果。修复后另建v2，旧日志／失败不改。trace_executor_build v2因元数据字符串转义patch不匹配，在编译前失败；v3修复后编译成功，派生C++ SHA256与已GPU验证v1完全相同，因此不重复GPU实验。

### 元数据修订与当前边界

snapshot executor旧v1／v2 device.json误继承`dxbc_unmodified:true`，与实际adapted program身份冲突。旧报告明确适配、原始字节及hash可复验；错误标签不作为原程序证据。当前build_snapshot_reference.py／派生源码及build v3改为false、explicit_snapshot_adaptation true，旧binary／raw不回写。trace build v1已正确标记两项；当前build v3源码与它相同。

D10已具备只读消费控制和局部同调用算术证据，但没有恢复原位真实读取流／可见顺序，也没有完整夹具、短序列和生命周期判据。G02继续进行中，G03／G04及T07不删减。下一步必须先建立有独立依据的逐运算误差／跨编译器模型，并继续核实原位读取配对；不可继续扩采样范围到候选通过。

技术事实已归档docs/competitor/水求解参考与同步.md的WATER-SNAPSHOT-ARITHMETIC-01及WATER-FP-JOINT-TRACE-01，并同步统一入口。所有自有GPU／编译进程已结束，释放本轮GPU占用。

归档复核：t06_snapshot_trace_archive_20261025_v1核验43个run／1373份归档artifact hash及新技术条目链接，无错误；包括失败与部分结果，不将归档完整性作为数值通过。当前六份snapshot shader均恢复冻结基线hash。新增／修改Python工具py_compile通过；GDScript和shader由实际GPU运行验证，未重跑无关生产测试。


## D11重排控制、表达式模型与完整快照闭合（G02仍进行中）

上一轮“相同MAD输入”的解释在本轮收紧：观察到的是名义寄存器副本，refactoringAllowed允许驱动重算或跨指令变换，不能据副本直接证明物理MAD操作数。新增独立声明许可控制区分该解释，旧raw、旧失败及旧模型检查原样保留。

- t06_token_header v1从固定Microsoft DXC commit1527671533a955c40a7e43a68f767fde734c4cb5取得原头；v2补齐同repo完整LICENSE.TXT，头内容相同。直接定义refactoringAllowed=1<<11，SDK实际解析核对清除后的声明。
- t06_strict_snapshot_dxbc v1只清许可位0x0100086a→0x0100006a，全部709执行指令token不改。strict_reference v1六小样本三次稳定、消费控制／3类拒绝通过；相对原许可输出word变化0／1／0／2／0／0。
- strict_snapshot_godot v1对原literal fma候选18次，只有速度3次未逐位相同（39word），平流差异消失。该严格副本是反事实控制，不替代原许可参考。
- 平流用第9条未乘scale的除法值与先f32(scale×dt)作FMA，名义中间值两分量全拟合；profile v8小样本仅速度仍40word，平流已逐位相同。
- t06_snapshot_reference_full v1覆盖既定72身份×3；全原许可snapshot副本，实际GPU水／snapshot／原SRV前态与fence逐次核实，全部稳定。t06_snapshot_rules_full v1冻结精确2097152 bytes、零额外允差，原位规则不替换。
- profile v8完整比较经恢复为216次，其中207逐位相同、9次失败：仅速度3身份，分别40／2503／8word，所有可见码误差最大1code；没有据此加1code容差。
- 速度drag joint保存114、116、118、119阶段：前两跨端相同，后两各35格不同。fma(v,-float32(depth×dt),v)拟合名义118全部格，literal mul后FMA35格不同，先1−depth×dt再乘3791格不同。profile v9小样本速度变39word，其余五核逐位相同。
- 速度DP2 joint：输入x／y跨端完全相同；先x²再fma(y,y,x²)与原生名义DP2全部相同，分开平方相加2826格、反向fma16022格不同。限速joint中，长度平方相同处rsq未见跨端差异，未宣称已恢复硬件rsq近似。

完整模型拟合、来源hash、控制与未知见t06_reassociation_models v1。CPU浮点probe只是诊断；其完整输出有额外码差，未被接受作GPU参考。fma32中间数组改为C连续以确保midpoint修正回写，t06_cpu_fma_audit v1以1024组三参数宽指数有符号样本／Fortran布局对照scalar UCRT fmaf，逐位相同；这不证明GPU浮点／FTZ模型。

profile v10仅加入有独立定位依据的三表达式，无坐标分支。小样本pilot v8为18/18逐位相同；完整snapshot_godot_full v3为72×3=216/216逐位相同，全部九字段及耦合位覆盖，零额外FP／quantization。t06_snapshot_aggregates v1另核72身份全部candidate的编码A和、解码A与h和、解码非有限值和最终B/source/sea/wet类别相同；源汇／边界／钳制贡献分解null，不冒充独立守恒证明。

当前项目profile v11只改v10文首标识注释与元数据，t06_profile_equivalence v1逐文件断言其余GLSL字节完全相同，不为注释重新跑全GPU矩阵。实际GPU验证source仍以v10及其完整run为准。原inplace shaders未加入这些模型，正式工程未接线。

### 完整矩阵的包装器与空间故障，均未重跑已有GPU数据

snapshot_godot_full v1在rule-freeze原句柄尚未终止时被误调用，缺rules.json，未启动Godot；保留失败后等待原freeze句柄完成，未重启freeze。v2实际GPU完成72 cases／216输出、释放468 RID及local device后，CPU比较写报告遇ENOSPC；原partial文件保留，evaluate_snapshot_run.py另在snapshot_full_recovery v1核完整GPU前态／CB／SRV／只读snapshot前后／shader／compiledSPIRV／输出长度与hash及sync括号，恢复216比较，无GPU重跑。原wrapper终止后PID／命令元数据未完整落盘，不补造；保留冻结request、launcher源码及原GPU结果。

D盘空间通过compact.exe透明无损压缩本任务原native矩阵和本轮full v2/raw恢复，并为新证据目录启用压缩继承。storage_recovery v1在0空间时hash读取也遇ENOSPC；v2另核旧矩阵5047份artifact，全部hash／长度保持相同。没有删除证据、改变逻辑路径或建立junction。

曾复制本轮native full/raw至C:/Users/18205/.codex/artifact-archives/sandcastle-water-solver/t06_snapshot_reference_full_20261025_v1/raw，1132份均核对冻结manifest hash；后续“删除D副本再建立junction”的请求被自动审批策略阻止，未执行。改为无损压缩恢复空间，D原始文件全部保留，C副本只作冗余备份，验证ledger复制到storage_recovery v2。无需用户批准该已放弃的迁移动作，也没有绕过审批。

C03文档v1.3仅更新已有快照证据和下一读流配对边界，reference_budget旧值不改，C04／C05文字逐字相同；快照t06_contract_boundary_snapshot v2。G02仍进行中：快照适配完整夹具闭合不代替未修改原位读取顺序，下一步实际读流capture／replay。G03短序列、原位与ping-pong分列、G04生命周期和T07范围均保留。GPU／编译进程已结束，只有归档审计可继续使用CPU。

冻结时间口径：full规则包含已在pilot精确零允差规则下比较过的6身份，以及首次完整比较前新增冻结的66身份。前6沿用原先零允差，不宣称full文件早于其历史pilot比较；旧规则文件的概括性时间文字不是时间证明，实际顺序由各parent manifest／进程receipt确定。未改旧文件／旧判定或任何限值，生成器后续文字已显式要求逐身份核对。

本批收尾索引：t06_snapshot_trace_archive v2核78个run／5535份归档artifact，hash／当前profile v11／技术条目链接核验无错误，失败也在索引。实际full GPU开始／结束为2026-10-25T15:44:18.153829+00:00／15:45:15.854518+00:00（本地25日23:44–23:45）；后续归档说明更新跨入本地2026-10-26，run_id继续沿用25日批次名，不将名称当时间依据。所有新增Python工具编译检查通过，无自有GPU或构建句柄待续。


## D12速度核读流小样本（2026-10-26，G02仍进行中）

先复核磁盘与真实状态：无旧GPU／构建句柄待续，D盘有约10 GB空间。按预登记路径实现读取记录与固定流重放，不重新采样旧经验包络。

### 字节码与执行器

- t06_readstream_dxbc_20261026_v1：capture与replay各215条指令，原速度核163条；capture保持全部原执行token为同顺序子序列，新增52条指令、2个temp及独立u1，不改u0别名／32×32／原算术／store／refactoringAllowed。replay只替换5个load的数据来源到t2，仍记录原计算位置。SDK反汇编、原token及文本子序列检查通过，原program不写回。
- 每调用5个有序读取，每读取2个uint4（元数据＋post-swizzle有效目的bits），131072调用共20971520 B；mask未写lane补零，只表示未记录。实际src偏移0，原指令5／7／12／16／18，mask3／15／15／12／15。源水完整2097152 B及CB2560 B分别保留。
- t06_readstream_executor_build v1构建成功。支持simple速度5-read capture和带20MiB --stream-input的replay；u1视图1310720元素、stride16，资源单独恢复／copy／fence。v2仅修复help误提floor/sources及其参数，C++其余字节完全相同，未假称v2另跑GPU；等价见readstream_tool_equivalence v1。

### 原生配对与拒绝

readstream_reference v1捕获3次，每次实际GPU水前态SHA同25867a63f09438647252b9dffee842f2cfe04d43aef7521c9bc14ba197432681、CB source SHA同1963297b76a0709be3cde8ffe1e2729f0114e87b0d848a5bd029dbe943a6c1b1，fence实际完成，输出3种hash。每份stream单独replay，完整2MiB正常输出与20MiB元数据／payload均精确相同；t2实际GPU前态hash、u0恢复和fence核验，零额外量化／FP允差，判据在第一次采集前写入request。

真实拒绝：原未插桩program缺u1、capture误带stream、replay缺stream、128 B截短stream。另改metadata一个mask bit、payload不变：正常输出仍同，但完整stream比较能检出，负例通过；不把正常输出相同当记录配对通过。

### Godot记录重放与报告守卫修复

make_readstream_glsl v1静态guard错误地把buffer声明也计入waterCells访问，抛WATER_READ_REMAINS，未写project／未启动GPU；失败保留。v2生成正常shader与独立stream_probe.gd／tscn，只从binding4消费记录payload，binding5记录原计算位置和值，正常u0独立输出；三表达式模型沿用已验证速度profile，原snapshot／inplace文件不改。

readstream_godot v1完成3份stream×3次的九组完整正常输出／stream逐位相同；实际CB／水初态／stream前后GPU hash及compiledSPIRV／submit-sync括号保存，释放21个RID与local device。整体manifest仍failed，因为wrong_identity先被正确拒绝，随后空返回又被extent检查覆盖错误字符串，导致该负例分类不满足预期；没有把失败manifest改绿。

v3只在_checked_bytes失败返回空后直接退出调用方，guards v1仅重跑错误身份并明确得到ARTIFACT_IDENTITY_MISMATCH、释放4 RID。静态复核同时补齐有效hash的空artifact拒绝（未把旧路径的潜在提前返回写成已发生挂起）：GLSL/probe v4在_checked_bytes显式EMPTY_ARTIFACT后返回，guards v2以实际进程分别验证wrong_identity与0 B正确hash空stream，均单一错误、非零退出并释放资源。截短和错误模式的旧实际拒绝仍保留；未为预检改动重跑九组数值正例。

pairing审计v1／v2／v3依次补强直接重算native hash关系、guard限定改动及空artifact控制。最新v3重新核172份artifact、原生3逐份replay、Godot9配对，正常输出和完整stream hash直接相同。当前shader v4与已测v2字节完全相同，当前probe只多两个预检提前拒绝路径，所有正例artifact均非空；代码等价与guard-only修复已核，不混称新增GPU正例。

### 三次读流差异的观察范围

| 捕获对 | 正常输出word差异 | 读取元数据word差异 | 加载结果word差异 |
|---|---:|---:|---:|
| 0／1 | 1677 | 0 | 4346 |
| 0／2 | 1593 | 0 | 3719 |
| 1／2 | 1884 | 0 | 4445 |

每份输出都由其记录流在native／Godot重放精确重现，支持所记读取值足以解释本次非唯一输出。与初态／对应完成态分类，第16条仅匹配完成态元组数4443／4831／4479；全部有效元组或匹配初态、或匹配完成态、或两者相同，未观察到单元组内混合分量或两态之外word。中心第18条没有仅匹配完成态元组。分类不当时间戳、向量原子性或全局调度证明。

这仍只是插桩速度核一个受控身份，不是未插桩原程序无扰动结果，不是Godot自身原位执行，不覆盖其余五核／完整夹具／短序列／生命周期。后续扩这些范围，不以本小样本关闭G02。已将技术事实与限制归档WATER-READSTREAM-01并同步README；C03文档v1.4补记录协议和限定配对，C04／C05全文未改，boundary snapshot为t06_contract_boundary_snapshot_20261026_v1。

补充来源身份守卫：生成器现按exact导出索引核原program／ASM与floor模板hash，collector绑定parent原program到参考身份，Godot wrapper绑定lowering到同一adaptation／parent ASM。readstream_identity_guards v1实际拒绝损坏校验字节的导出副本、相同布局却parent不匹配的native配置及Godot lowering parent不匹配，均在GPU request创建前退出。原源与原成功数据不改；这些只增加主机预检，不重跑正例。

D12归档收口：t06_snapshot_trace_archive_20261026_v1核97个run／5807份artifact、当前snapshot v11及stream v4实际源码／scene／probe hash、技术条目链接，无错误。新增七个Python工具及更新的archive工具py_compile通过。全小样本进程及归档审计已终止；无GPU／构建句柄待续，G02与总体25/32不变。


后续六核双向读流及完整矩阵中断的当前整理见[T06_readstream_20261026.md](T06_readstream_20261026.md)；以上“速度单身份／当前未执行”等描述均保留其历史范围，不覆盖最新执行状态。G02、G03、G04及T07未关闭。
