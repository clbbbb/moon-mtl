"""Count nonempty, non-line-comment MoonBit lines; exclude build/generated data."""
import argparse
from collections import Counter
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    groups = Counter()
    files = {}
    for path in sorted(ROOT.rglob("*.mbt")):
        relative = path.relative_to(ROOT)
        if any(p in {"_build", ".mooncakes", "target"} for p in relative.parts):
            continue
        group = ("tests" if path.name.endswith(("_test.mbt", "_wbtest.mbt")) else
                 "cli" if "cmd" in relative.parts else
                 "scenarios" if "scenarios" in relative.parts else "core")
        count = sum(bool(line.strip()) and not line.lstrip().startswith("//")
                    for line in path.read_text(encoding="utf-8-sig").splitlines())
        files[relative.as_posix()] = count
        groups[group] += count
    result = {"method": "nonblank non-line-comment *.mbt; build, dependencies and generated interfaces excluded",
              "groups": dict(groups), "total": sum(groups.values()), "files": files}
    output = ROOT / "reports/source-count.json"
    if args.check:
        assert json.loads(output.read_text(encoding="utf-8")) == result, "source count report is stale"
    else:
        output.parent.mkdir(exist_ok=True)
        output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    assert result["total"] > 4000, result
    print(json.dumps({"groups": result["groups"], "total": result["total"]}))


if __name__ == "__main__":
    main()
