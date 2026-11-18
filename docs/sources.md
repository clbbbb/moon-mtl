# 来源、相邻项目和许可证

本仓库的 MoonBit 实现未复制第三方监测器代码，也不链接 Reelay。三个场景日志由本仓库的确定性场景程序生成，不含真实用户、设备或业务数据。MoonBit 标准库是唯一核心依赖；Node.js 文件接口仅用于命令行。

参考资料：

- [Reelay 规则语言](https://doganulus.github.io/reelay/rye/)，用于核对时序运算的通用概念。
- [Reelay 输入行为](https://doganulus.github.io/reelay/behaviors/)，用于区分离散采样与保持信号的语义。
- [Reelay 仓库](https://github.com/doganulus/reelay)：外部相关实现，主仓库许可证 MPL-2.0；不作为本仓库的源代码来源。
- [时间流监测论文](https://kmamouras.github.io/papers/monitoring-RV%2720-extended.pdf)：算法背景阅读，不表示本库实现了论文全部功能或性能保证。
- [moon-statelens](https://github.com/CaptainK-65/moon-statelens)：相邻方向为黑盒 Mealy 模型学习与有限安全规则。MoonMTL 关注带时间边界的嵌套过去时规则，不做自动机学习。
- [veri](https://github.com/mizchi/veri)：相邻方向为验证基础设施。MoonMTL 提供具体的日志规则执行器，不声称替代通用形式化验证工具。

本次性能实验只比较本项目的三种执行方式，没有测量 Reelay、statelens 或 veri。不同输入语义、实现语言和功能边界不能直接换算成性能结论。现有生态会继续变化，选题调研不能保证未来无人实现类似功能。

根目录 LICENSE 为 Apache-2.0。`*.generated.mbti` 是 MoonBit 工具生成的接口摘要，不计入手写代码统计；实验数据和样例事件为生成数据，也不计入 MoonBit 行数。当前项目由编程助手辅助实现；代码、测试与说明均应由申报人复核，不隐瞒辅助工具的使用。
