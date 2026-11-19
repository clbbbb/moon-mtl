# MoonMTL

MoonMTL 用来检查带时间戳的事件日志：发送数据前是否完成握手、任务执行时租约是否仍有效、设备报告恢复前是否经过了一段稳定观测。规则可以嵌套，多个规则可以共享子表达式。

项目实现有界过去时度量时序逻辑（Past MTL）。输入是严格递增的非负 Int64 时间戳，以及各命题在该次观测中的布尔值。核心库只依赖 MoonBit 标准库，支持 wasm、wasm-gc 和 JavaScript；文件命令行使用 Node.js。

```text
send -> once[1,12] handshake
working -> (allowed since[0,8] renew)
recovered -> historically[0,4] healthy
```

第一条规则表示：观察到 send 时，必须在过去 1～12 个时间单位内观察到 handshake。时间单位由调用者统一约定。

## 运行

本地验证环境为 MoonBit 0.10.19。Node.js 22 及以上用于命令行，Python 3 用于复现实验。

```powershell
moon check --deny-warn
moon test --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon run --target js cmd/main scenario handshake 240
moon run --target js cmd/main scenario lease 240
moon run --target js cmd/main scenario recovery 240
```

当前工具链直接在包路径后传参数。编译后的命令也可以直接调用：

```powershell
moon build --target js --release --deny-warn
node _build/js/release/build/cmd/main/main.js --help
node _build/js/release/build/cmd/main/main.js replay examples/rules.json examples/events.jsonl
python scripts/verify_cli.py
python scripts/benchmark.py
python scripts/count_source.py
```

`rules <场景>` 输出规则文档，`export <场景> <数量>` 输出 JSONL 日志，`bench <场景> <数量>` 输出基准原始记录。三个场景都包含正常与违规路径。

## 在其他 MoonBit 项目中使用

在依赖配置中导入本模块并指定别名 `@mtl`。库的基本调用顺序如下：

```moonbit
let plan = @mtl.Plan::from_strings([
  ("send_checked", "send -> once[1,12] handshake"),
]).unwrap()
let monitor = @mtl.Monitor::new(plan)
let observation = @mtl.Observation::new(
  0L,
  Map([("send", false), ("handshake", true)]),
).unwrap()
let decision = monitor.push(observation).unwrap()
let verdict = decision.value("send_checked")
```

`Plan` 是可共享的编译结果；每个 `Monitor` 独立持有更新状态。`Reference` 是独立递归解释器，用于核对结果，不作为快速执行路径。`Audit` 统计每条规则的通过数、失败数、连续失败段和首次/末次失败位置，不保存整个日志。

`JsonlSession.feed` 接收字符串块，完成一行后提交事件。`feed_each` 在每一行提交后立即交付判定，后续坏行不会丢掉前缀判定。`finish` 处理最后一个未换行的记录。每块、每条记录最多 1,048,576 个 UTF-16 代码单元。会话遇错后关闭。CLI `replay` 以 64 KiB 的块读取文件，逐行严格解码 UTF-8，将判定写到标准输出。

## 数据与结果校验

事件示例：

```json
{"time":"9007199254740993","values":{"send":false,"handshake":true}}
```

时间戳使用十进制字符串，覆盖完整非负 Int64，避免 JavaScript 的浮点整数精度问题。每次观测都必须提供计划所需的全部命题；不会把缺失命题猜成 false，也不会沿用上一条的值。重复键、未知结构字段、非布尔命题值会被拒绝。

`Decision.to_json` 和 `Plan.decision_from_json` 支持传输结果。解码只检查结构；需要提供输入日志并调用 `Plan.verify_decision` 才能检查结果是否正确。`Monitor.explain` 返回相关节点、时间窗口、见证及 Since 的阻断位置，`Plan.verify_evidence` 用独立解释器校验这些片段。

见证不是签名，也不是对现实世界完整性的证明。`verify_evidence` 检查片段的正确性，不保证调用者提交的片段包含完整解释。详细语义和预算见 [语义说明](docs/semantics.md)。

## 实现与证据

解析器把规则编译成拓扑排序 DAG，相同子表达式只计算一次。Once 保存满足条件的候选，Historically 保存反例候选，Since 在左式为假时清除旧见证。队列使用逻辑头和分段回收，避免每次移动整个数组。单条更新先检查并计算，再统一提交；时间戳、命题和候选预算错误都不会改变监测器状态。

测试包括随机嵌套公式差分、短轨迹穷举、时序恒等式、时间平移、规则重排、长轨迹队列回收、错误后重试、传输数据拒绝和见证篡改。核心库、测试、命令行和场景代码的分项统计见 [源代码统计](reports/source-count.json)。

三组对照实验使用相同的确定性日志，对比共享 DAG、每条规则独立监测以及离线递归解释器。原始数据、环境和局限见 [实验报告](reports/benchmark.md)。这些是合成的应用日志，不代表真实生产部署，也没有据此声称优于 Reelay。

本轮改进使用哈希去重、过期位置下界查找、时序提交调度和数组复用，并为规则查询建立索引。改动前后使用相同日志重新测量，见 [算法优化对照](reports/algorithm-comparison.md)。

## 范围

目前不支持未来时运算、乱序到达、连续时间插值、任意数值谓词或自动学习协议。若应用需要“数值超过阈值”，应先在应用层生成明确的布尔命题。Previous 指上一条观测，不是上一毫秒。

这是独立实现，算法依据时序逻辑语义和公开文献。与现有项目的关系及许可证记录见 [来源说明](docs/sources.md)。许可证为 Apache-2.0。

源码仓库见 [clbbbb/moon-mtl](https://github.com/clbbbb/moon-mtl)。在使用本库的 MoonBit 项目中运行 `moon add clbbbb/moon-mtl@0.1.0` 安装。
