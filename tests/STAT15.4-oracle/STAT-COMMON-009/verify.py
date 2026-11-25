#!/usr/bin/env python3
"""Replay the unchanged full oracle; whitespace is the only normalization.

Every label, coefficient, estimate and missing-value token is compared. An
independent rational calculation also checks observed-cell means, error SS,
and the two estimable shared-level main-effect contrasts against the source.
"""
import argparse
import difflib
from fractions import Fraction as F
import hashlib
import json
from pathlib import Path
import subprocess


def reference(source):
    rows = [line.split() for line in source.split("datalines;", 1)[1].split(";", 1)[0].splitlines() if line.strip()]
    cells = {}
    for i, row in enumerate(rows, 1):
        group, h, y = row[3], i % 2, F(row[2])
        if group == "B" and h == 1:
            continue
        cells.setdefault((group, h), []).append(y)
    means = {k: sum(v) / len(v) for k, v in cells.items()}
    sse = sum((y - means[k]) ** 2 for k, values in cells.items() for y in values)
    contrasts = {}
    for name, left, right in (("group", ("A", 0), ("B", 0)), ("h", ("A", 0), ("A", 1))):
        contrasts[name] = (means[left] - means[right]) ** 2 / (F(1, len(cells[left])) + F(1, len(cells[right])))
    return means, sse, contrasts


def main():
    folder = Path(__file__).resolve().parent
    repo = folder.parents[2]
    parser = argparse.ArgumentParser()
    parser.add_argument("--exe", type=Path, default=repo / "zig-out/bin/opensas")
    parser.add_argument("--out", type=Path, default=repo / ".zig-cache/stat-common-009-evidence")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    source = folder / "estimability.sas"
    expected_file = folder / "estimability.expected.txt"
    expected = expected_file.read_text()
    result = subprocess.run([str(args.exe.resolve()), str(source)], cwd=args.out, capture_output=True, text=True)
    (args.out / "actual.txt").write_text(result.stdout)
    (args.out / "actual.log").write_text(result.stderr)
    (args.out / "actual.rc").write_text(str(result.returncode) + "\n")
    expected_tokens, actual_tokens = expected.split(), result.stdout.split()
    diff = "\n".join(difflib.unified_diff(expected_tokens, actual_tokens, fromfile="SAS", tofile="OpenSAS", lineterm=""))
    (args.out / "raw-token.diff").write_text(diff)
    assert result.returncode == int((folder / "estimability.expected.rc").read_text()), result.stderr
    assert expected_tokens == actual_tokens, diff
    means, sse, contrasts = reference(source.read_text())
    for text in (expected, result.stdout):
        rows = [line.split() for line in text.splitlines()]
        for (group, h), value in means.items():
            row = next(row for row in rows if len(row) == 3 and row[:2] == [group, str(h)])
            assert abs(F(row[2]) - value) <= F(1, 2 * 10**7)
        error = next(row for row in rows if row and row[0] == "Error")
        assert F(error[2]) == sse
        type3 = text.split("Type III SS", 1)[1].split("Least Squares Means", 1)[0]
        for name, value in contrasts.items():
            row = next(line.split() for line in type3.splitlines() if line.split()[:1] == [name])
            assert F(row[2]) == value
    report = {"status": "pass", "exit_status": result.returncode,
              "expected_tokens": len(expected_tokens), "actual_tokens": len(actual_tokens),
              "raw_token_differences": 0, "normalization": "whitespace only",
              "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
              "expected_sha256": hashlib.sha256(expected_file.read_bytes()).hexdigest(),
              "cell_means_exact": {str(k): str(v) for k, v in means.items()},
              "error_ss_exact": str(sse), "type_iii_ss_exact": {k: str(v) for k, v in contrasts.items()}}
    (args.out / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
