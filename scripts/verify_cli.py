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
        # Put the first byte of a multibyte character at the end of a read.
        second = '{"time":"9007199254740994","values":{"p":false,"é":true}}'
        prefix, suffix = second.split("é")
        padding = 65535 - len((first + "\n" + prefix).encode("utf-8"))
        trace.write_bytes((first + "\n" + " " * padding + prefix + "é" + suffix).encode("utf-8"))
        result = invoke("replay", rules, trace, ok=False)
        assert "line 2" in result.stderr and "invalid observation atom name" in result.stderr
        assert len(result.stdout.splitlines()) == 1
        second = second.replace("é", "q")
        trace.write_bytes((first + "\n" + " " * padding + second).encode("utf-8"))
        assert len(invoke("replay", rules, trace).stdout.splitlines()) == 2
        # Each line is below the record budget, while the whole file exceeds
        # the previous CLI limit of 16 MiB.
        with trace.open("wb") as out:
            for time in range(20):
                record = json.dumps({"time": str(time), "values": {"p": True}}).encode()
                out.write(b" " * 900000 + record + b"\n")
        assert len(invoke("replay", rules, trace).stdout.splitlines()) == 20
        trace.write_bytes((first + "\n" + second + "\n").encode("utf-8") + b"\xff\n")
        result = invoke("replay", rules, trace, ok=False)
        assert "line 3: invalid UTF-8" in result.stderr
        assert len(result.stdout.splitlines()) == 2
        trace.write_bytes((first + "\n").encode("utf-8") + b" " * (3 * 1048576 + 1))
        result = invoke("replay", rules, trace, ok=False)
        assert "line 2" in result.stderr and "budget" in result.stderr
        assert len(result.stdout.splitlines()) == 1
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
