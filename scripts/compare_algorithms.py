"""Compare recorded revisions without rerunning or changing their inputs."""
import argparse
import json
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    before = json.loads((ROOT / "reports/algorithm-before.json").read_text())
    after = json.loads((ROOT / "reports/benchmark-raw.json").read_text())
    assert before["metadata"]["trace_sha256"] == after["metadata"]["trace_sha256"]
    lines = [
        "# 算法优化前后对照",
        "",
        f"优化前执行版本：`{before['metadata']['revision']}`；优化后执行版本：`{after['metadata']['revision']}`。",
        "",
        "同一台机器、相同日志 SHA-256、相同 release 构建方式。每组保留 7 轮，去掉第 0 轮后取中位数。表内仅比较共享 DAG 路径；全部执行路径原始结果仍分别保存在两个 JSON 文件中。",
        "",
        "| 场景 | 事件数 | 优化前 ms | 优化后 ms | 耗时减少 |",
        "|---|---:|---:|---:|---:|",
    ]
    for key in before["metadata"]["trace_sha256"]:
        name, count = key.split("/")
        select = lambda data: [r for r in data["runs"] if r["scenario"] == name and r["events"] == int(count)]
        old, new = select(before), select(after)
        assert len(old) == len(new) == 7
        assert {r["checksum"] for r in old} == {r["checksum"] for r in new}
        assert {r["peak_candidates"] for r in old} == {r["peak_candidates"] for r in new}
        a = statistics.median(r["shared_ms"] for r in old if r["repetition"] > 0)
        b = statistics.median(r["shared_ms"] for r in new if r["repetition"] > 0)
        lines.append(f"| {name} | {count} | {a:.3f} | {b:.3f} | {(a-b)/a*100:.1f}% |")
    lines.extend([
        "",
        "改动包括：哈希去重、规则批次预检查、候选过期下界查找、预编译时序提交列表、节点值双缓冲、队列暂存数组复用、规则名索引。原子更新和公开逻辑语义保持不变；同时存在名称和公式错误时，批次预检查会先报告名称错误。",
        "",
        "这些是整组改动的端到端测量，没有逐项消融，不能把收益分别归因到某一项。三个场景的队列较小，不用于证明大队列查找的性能；大跨度过期查找另有边界与线性结果对照测试。没有测量分配器或堆内存，减少分配来自实现路径审查。",
        "",
        "两次测量并非随机交错，系统负载、JIT 和 GC 都可能影响结果；不能承诺其他机器获得相同比例。正确性同时由独立参考解释器、逐规则差分及错误后重试测试核对。",
        "",
        "复核：`python scripts/compare_algorithms.py --check`。重新基准：`python scripts/benchmark.py`，再运行不带 `--check` 的比较脚本。",
    ])
    text = "\n".join(lines) + "\n"
    path = ROOT / "reports/algorithm-comparison.md"
    if args.check:
        assert path.read_text(encoding="utf-8") == text, "comparison report is stale"
    else:
        path.write_text(text, encoding="utf-8")
    print(text)


if __name__ == "__main__":
    main()
