# 旧shader原件权威重放复核

结论：旧水面及水侧shader原件、岸脚gain1的A/A也未逐字节一致；不是只观察新shader中的mode0分支。原始字段与历史比较仍失败，不增加epsilon，不认定A/B无额外影响，不据相近量级通过G4。

进程退出1，未超时，源码前后无漂移，stderr为空。499项检查中22项失败均为权威字段/历史比较；准入、finish、END空、每tick恰好+1、恢复、释放、无孤儿及原件身份检查通过。

| 变体 | 水面代码SHA256 | 水侧代码SHA256 | 岸脚gain |
|---|---|---|---:|
| case0、case1 | 26a503bd375f88e43f7b1a7fdac1812fd2d7da4ad4217423aa5ae6d398ed0a61 | d69f77b8bd03a78461fb29ff5fd8084e1fc68b43b30ac9c0319a9b6dee757462 | 1 |
| case2 | 当前正式代码，实际SHA及getter参数见analysis.json/variants | 当前正式代码，实际SHA及getter参数见analysis.json/variants | 0.55 |

三个变体由同一start.sandue恢复，执行同样填沙+30tick、挖沙+30tick，无中间保存。实际ShaderMaterial getter已记录，旧材质用内存代码SHA，不对空resource_path求文件hash。

| 字段（原单位） | 原件/原件AA最大绝对差 | 原件/正式AB最大绝对差 |
|---|---:|---:|
| sand | 5.960464478e-8 | 5.960464478e-8 |
| water | 2.980232239e-8 | 5.960464478e-8 |
| momentum_x | 1.769512892e-8 | 1.405715011e-8 |
| momentum_z | 2.607703209e-8 | 1.885928214e-8 |
| sediment | 3.492459655e-10 | 3.492459655e-10 |
| flux | 3.434251994e-9 | 3.958120942e-9 |

完整分量数量、原始native组与configuration/simulation/selection/wave/tick/time精确比较见analysis.json。该对照仍使用当前物理源码、UI和场景负载；它只换回了精确旧水面/水侧代码与岸脚增益，不冒称整个历史工程重放，也不声称根因发生在旧shader里。

初轮exact_original_authority_v1在比较开始前主动终止：继承的素材记录器不适用于无文件路径的内存Shader。未完成样本、源码副本及终止原因保留于原目录，不算通过或有效A/A。v2只修正记录方式并补齐水侧原件，不改变权威实现。
