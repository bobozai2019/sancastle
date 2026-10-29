# ADR：实验完成态初始化 v1

日期：2026-10-11。状态：accepted，限本专项隔离实验。原因EV-003：原GPU initialize对flux、交替输出及辅助纹理使用空payload创建；不能仅由创建成功推断这些字节已定义，也不能把未定义flux遗漏后宣称完整初态重置一致。

实验后端`lab_solver.gd`继承原gpu_shallow_solver，仅覆写_create_texture：调用者已给数据时保留；空数据时按真实format/尺寸显式填零，再沿原创建路径。原pass、CFL、物理公式、源汇与格式不变；不更改正式后端。flux在首tick之前即为显式零RGBA32F，并纳入原始快照与重复初始化逐位比较。其余辅助场为派生工作缓冲，零初值不构成新的物理输入。

numeric、brush和beach候选共用此工厂规则；正式场景资源/profile保持继承，beach候选仅替换隔离script和continuous wave workload。T06新A/B均需同初始化，不能用额外清零开销混入只一组的成本或把旧非同态历史窗口当新A。

重置/释放先将所有Texture2DRD的texture_rd_rid解绑为RID()，再释放proxy/solver资源；新generation与新RID就绪后绑定。失败运行011820中原顺序导致Attempted to free invalid ID，保留为测试失败，后续无错误才计通过。

范围反证：若填零改变第一有效pass输出、继承正式profile失配、flux/任一权威初态不能重复，G1不通过。本次证据见T02报告；这不是“正式后端存在未初始化数值污染”的已证实结论，只证实原初始化未显式提供这些payload及实验规则已补齐。
