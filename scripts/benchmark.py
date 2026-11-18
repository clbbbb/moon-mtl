"""Record actual release measurements; retain cold run, summarize warm medians."""
import datetime
import hashlib
import json
import platform
from pathlib import Path
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "_build/js/release/build/cmd/main/main.js"
OUT = ROOT / "reports"


def command(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True, encoding="utf-8").strip()


def main():
    OUT.mkdir(exist_ok=True)
    records = []
    traces = {}
    for name in ["handshake", "lease", "recovery"]:
        for size in [1200, 4800]:
            output = command("node", str(CLI), "bench", name, str(size))
            rows = [json.loads(line) for line in output.splitlines()]
            assert len(rows) == 7
            assert len({r["checksum"] for r in rows}) == 1
            records.extend(rows)
            trace = command("node", str(CLI), "export", name, str(size))
            traces[f"{name}/{size}"] = hashlib.sha256(trace.encode()).hexdigest()
    metadata = {
        "utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "revision": command("git", "rev-parse", "HEAD"),
        "platform": platform.platform(), "processor": platform.processor(),
        "node": command("node", "--version"), "moon": command("moon", "version"),
        "build": "moon build --target js --release --deny-warn",
        "trace_sha256": traces,
        "method": "seven repetitions; repetition zero retained but excluded from median; fixed shared/independent/reference order; construction excluded",
    }
    (OUT / "benchmark-raw.json").write_text(json.dumps({"metadata": metadata, "runs": records}, ensure_ascii=False, indent=2), encoding="utf-8")
    lines = ["| scenario | events | shared ms | independent ms | reference ms | nodes shared/independent | peak candidates | checksum |",
             "|---|---:|---:|---:|---:|---:|---:|---:|"]
    for key in traces:
        name, size = key.split("/")
        rows = [r for r in records if r["scenario"] == name and r["events"] == int(size) and r["repetition"] > 0]
        medians = [statistics.median(r[field] for r in rows) for field in ["shared_ms", "independent_ms", "reference_ms"]]
        first = rows[0]
        lines.append(f"| {name} | {size} | {medians[0]:.3f} | {medians[1]:.3f} | {medians[2]:.3f} | {first['shared_nodes']}/{first['independent_nodes']} | {first['peak_candidates']} | {first['checksum']} |")
    (OUT / "benchmark-table.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
