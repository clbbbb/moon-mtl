"""Exercise the compiled public command, including its process exit status."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "_build/js/release/build/cmd/main/main.js"


def invoke(*args, ok=True):
    result = subprocess.run(["node", str(CLI), *map(str, args)], cwd=ROOT,
                            capture_output=True, text=True, encoding="utf-8")
    assert result.returncode == (0 if ok else 2), (args, result.stdout, result.stderr)
    return result


def main():
    assert "MoonMTL" in invoke("--help").stdout
    for args in [("unknown",), ("scenario", "lease", "0"),
                 ("scenario", "lease", "1000001"),
                 ("scenario", "lease", "oops"),
                 ("scenario", "unknown", "3"), ("rules", "unknown")]:
        invoke(*args, ok=False)
    with tempfile.TemporaryDirectory(prefix="moonmtl-") as directory:
        directory = Path(directory)
        for name in ["handshake", "lease", "recovery"]:
            rules = directory / f"{name}.json"
            trace = directory / f"{name}.jsonl"
            rules.write_text(invoke("rules", name).stdout, encoding="utf-8")
            trace.write_text(invoke("export", name, "240").stdout, encoding="utf-8")
            records = [json.loads(line) for line in trace.read_text().splitlines()]
            verdicts = [json.loads(line) for line in invoke("replay", rules, trace).stdout.splitlines()]
            assert len(verdicts) == len(records) == 240
            assert all(v["position"] == i and v["time"] == records[i]["time"]
                       for i, v in enumerate(verdicts))
            assert all(len(v["verdicts"]) == 5 for v in verdicts)
            assert "events=240" in invoke("scenario", name, "240").stdout
        rules.write_text('{"version":"1","rules":[{"name":"r","formula":"p"}]}', encoding="utf-8")
        first = '{"time":"9007199254740993","values":{"p":true}}'
        trace.write_text(first + "\ninvalid\n", encoding="utf-8")
        result = invoke("replay", rules, trace, ok=False)
        assert "line 2" in result.stderr
        assert json.loads(result.stdout)["time"] == "9007199254740993"
        trace.write_text(first + "\n" + first, encoding="utf-8")
        assert "line 2" in invoke("replay", rules, trace, ok=False).stderr
        trace.write_text("\n", encoding="utf-8")
        invoke("replay", rules, trace, ok=False)
        rules.write_text("{}", encoding="utf-8")
        invoke("replay", rules, trace, ok=False)
        invoke("replay", directory / "absent", trace, ok=False)
    print("CLI end-to-end verification passed (three scenarios and rejection paths)")


if __name__ == "__main__":
    main()
