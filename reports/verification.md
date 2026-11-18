# 本地交付检查

检查日期：2026-11-18。路径：`moon-mtl`。MoonBit 编译器为 `v0.10.19+bee578715`，moon 为 `0.1.20261102`。

| 检查 | 本地结果 |
|---|---|
| `moon check --deny-warn` | 通过 |
| `moon check --target wasm-gc --deny-warn` | 通过 |
| `moon check --target js --deny-warn` | 通过 |
| wasm / wasm-gc / js 构建 | 全部通过 |
| `moon test --target wasm --deny-warn` | 85 / 85 |
| `moon test --target wasm-gc --deny-warn` | 85 / 85 |
| `moon test --target js --deny-warn` | 88 / 88，含 3 项命令行内部测试 |
| release Node 命令行端到端检查 | 三场景及拒绝路径通过 |
| 示例 replay | 3 条结果依次为 true、true、false |
| `moon info`、`moon fmt` | 已执行 |
| 代码量 | 4020，计数规则及逐文件明细见 source-count.json |

核心库 1793 行，测试 1867 行，命令行 222 行，场景 138 行。计数包含实际代码中的结构性括号，不包含空行、整行注释、工具生成接口、依赖、构建目录和样例数据。没有通过生成大量事件、重复声明或注释补足行数。

交付覆盖：全部布尔运算及 Previous / Once / Historically / Since，闭区间与完整非负 Int64 时间戳，共享 DAG、在线队列、独立离线解释器、工作预算、原子更新、见证核验、JSON/JSONL、增量字符串会话、审计统计、三场景、对照实验、中文说明与 CI。

随机差分使用固定种子，生成 240 个深度 3 的公式，每个包含 24 条不规则采样记录；短轨迹枚举覆盖 14 组 Since 区间和每组 256 条四位置布尔轨迹。另有 1200 条长轨迹差分和 2500 条队列物理存储不变量检查。各后端重跑同一组核心测试。

目前没有远端仓库地址、远端 CI 结果或 Mooncakes 发布记录。本文件记录本地技术完成情况，不表示完成线上发布或已获得比赛验收。发布时需要填写 moon.mod 的 repository，创建远端、推送、查看 CI，再执行 Mooncakes 发布并核对公开包内容。比赛资格和提交时间应以实际参赛届次及赛方通知为准。
