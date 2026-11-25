#!/usr/bin/env python3
"""Replay the unchanged COMMON011 program and compare every listing token.

Only whitespace is normalized. No numbers, titles, labels, tables, or rows are
removed, and the real process status is checked. A separate exact-rational
calculation reads the source data and verifies the displayed Type II SS and F.
"""
import argparse
import difflib
from fractions import Fraction as F
import hashlib
import json
from pathlib import Path
import subprocess


# Reuse the independent rational solver from COMMON010 verification, never
# any production fit or its output. The two tickets share the same source data.
from runpy import run_path
sse = run_path(str(Path(__file__).resolve().parent.parent / "STAT-COMMON-010/verify.py"))["sse"]


def reference(source):
    rows = [line.split() for line in source.split("datalines;", 1)[1].split(";", 1)[0].splitlines() if line.strip()]
    x = [[F(1), F(1 if row[3] == "A" else -1), F(row[0]), F(row[1])] for row in rows]
    y = [F(row[2]) for row in rows]
    full = sse(x, y)
    # All three effects are main effects: none contains another. Type II
    # adjusts each target for all the other effects, unlike sequential Type I.
    effect_ss = [sse([[v for k, v in enumerate(row) if k != j] for row in x], y) - full
                 for j in range(1, 4)]
    mse = full / (len(rows) - 4)
    return effect_ss, mse


def independent_check(text, expected_ss, mse):
    checks = []
    for name, ss in zip(("group", "x", "z"), expected_ss):
        fields = next(line.split() for line in text.splitlines()
                      if len(line.split()) == 6 and line.split()[:2] == [name, "1"])
        for column, value in ((2, ss), (3, ss), (4, ss / mse)):
            token = fields[column]
            decimals = len(token.split(".")[1]) if "." in token else 0
            assert abs(F(token) - value) <= F(1, 2 * 10 ** decimals), (name, token, value)
        checks.append({"effect": name, "df": 1, "ss_exact": str(ss), "f_exact": str(ss / mse)})
    return checks


def main():
    folder = Path(__file__).resolve().parent
    repo = folder.parents[2]
    parser = argparse.ArgumentParser()
    parser.add_argument("--exe", type=Path, default=repo / "zig-out/bin/opensas")
    parser.add_argument("--out", type=Path, default=repo / ".zig-cache/stat-common-011-evidence")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    source = folder / "unbalanced_sums_of_squares.sas"
    expected_file = folder / "unbalanced_sums_of_squares.expected.txt"
    expected = expected_file.read_text()
    result = subprocess.run([str(args.exe.resolve()), str(source)], cwd=args.out, capture_output=True, text=True)
    (args.out / "actual.txt").write_text(result.stdout)
    (args.out / "actual.log").write_text(result.stderr)
    (args.out / "actual.rc").write_text(str(result.returncode) + "\n")
    expected_tokens, actual_tokens = expected.split(), result.stdout.split()
    diff = "\n".join(difflib.unified_diff(expected_tokens, actual_tokens, fromfile="SAS", tofile="OpenSAS", lineterm=""))
    (args.out / "raw-token.diff").write_text(diff)
    assert result.returncode == int((folder / "unbalanced_sums_of_squares.expected.rc").read_text()), result.stderr
    assert expected_tokens == actual_tokens, diff
    effect_ss, mse = reference(source.read_text())
    independent_check(expected, effect_ss, mse)
    checks = independent_check(result.stdout, effect_ss, mse)
    report = {
        "status": "pass", "exit_status": result.returncode,
        "expected_tokens": len(expected_tokens), "actual_tokens": len(actual_tokens),
        "raw_token_differences": 0, "normalization": "whitespace only",
        "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "expected_sha256": hashlib.sha256(expected_file.read_bytes()).hexdigest(),
        "mse_exact": str(mse), "independent_effect_checks": checks,
    }
    (args.out / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
