#!/usr/bin/env python3
"""Replay unchanged COMMON012; compare every token/status and both SS tables.

This particular oracle has only main effects, so none is contained in another.
Its III and IV hypotheses both equal the independently computed conditional
tests. This verifier does not claim that identity for arbitrary missing cells.
"""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import re
from runpy import run_path
import subprocess


def check_tables(text, reference):
    sections = re.split(r"Source\s+DF\s+Type\s+(III|IV)\s+SS", text)
    assert len(sections) == 5 and sections[1::2] == ["III", "IV"], "Expected complete III and IV tables"
    helper = run_path(str(Path(__file__).resolve().parent.parent / "STAT-COMMON-011/verify.py"))
    ss, mse = helper["reference"](reference)
    return [{"type": sections[i], "effects": helper["independent_check"](sections[i + 1], ss, mse)}
            for i in (1, 3)]


def main():
    folder = Path(__file__).resolve().parent
    repo = folder.parents[2]
    parser = argparse.ArgumentParser()
    parser.add_argument("--exe", type=Path, default=repo / "zig-out/bin/opensas")
    parser.add_argument("--out", type=Path, default=repo / ".zig-cache/stat-common-012-evidence")
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
    check_tables(expected, source.read_text())
    checks = check_tables(result.stdout, source.read_text())
    report = {
        "status": "pass", "exit_status": result.returncode,
        "expected_tokens": len(expected_tokens), "actual_tokens": len(actual_tokens),
        "raw_token_differences": 0, "normalization": "whitespace only",
        "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "expected_sha256": hashlib.sha256(expected_file.read_bytes()).hexdigest(),
        "independent_hypothesis_checks": checks,
    }
    (args.out / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
