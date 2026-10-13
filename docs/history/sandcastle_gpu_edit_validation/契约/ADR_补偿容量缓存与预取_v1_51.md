# ADR v1.51：补偿容量缓存与工作组预取

2026-10-11。承接v1.50，候选默认关闭，原版与失败证据保留。--cached-capacity需同时--packed-runs及--compensated-capacity选择water_packed_cached.glsl，普通恢复签名记录开关及源hash。

每tile64个lane分别预取two-sum surface和receiver room，lane0仍按原行序求最大及Kahan demand/capacity。容量room原生float bits写入既有5N scratch的空闲segment3，接收分配读取同一值，避免第二次计算。segment0标签、1连续索引、2分量/行前缀保持；33分量超限在使用缓存前回退，serial补偿仍初始化原scratch。缓存仅对域内接收格写入且仅由相同接收格读取，barrier及memoryBarrierBuffer明确处理工作组/SSBO可见性。无新增buffer或CPU生产读回，共享增加64 vec2+64 float即768字节，仍小于32KiB。

141703全拓扑27/28 PASS，仅原natural64沙审计拒绝保留。对比v1.50的141125：658份原生bin全部raw SHA相同（644有效、14前命令临时收据），并非只归一fast_path标记后相同；原始结果和hash索引保留。

141748可见1080p/D3D12/GTX1050/VSync-off原完整沙滩暂停事务窗口，C/B/D/E碰撞反馈90.171/52.385/90.891/97.244ms均PASS；末笔发布/碰撞/完整负载继续PASS。64对GPU时间戳无缺对，C/E位移26.664960/27.108352ms，对比v1.50约29.6/30.3ms减约3ms；速度账本约12ms。此单轮和跨源码定位不是正式交错A/B，不证明first-visible/连续成本，也不回写141240 E100.572ms失败。

候选不正式放行。组合E回归结果另附；普通严格恢复间歇差异、首可见、持续输入和T06成本/长稳门保持，G4及76.2%不变。

141814组合E56项全部PASS，与141322的3192 raw bin逐位一致（3080有效、112前态临时收据）。运行已终止，完整索引更新；详见验收/T05_补偿容量缓存与数值成本.md。
