#!/usr/bin/env python3
"""Unchanged original replay; complete listing/status and independent ANCOVA.

Only whitespace is normalized. The independent calculation uses within-group
centered crossproducts and exact rationals, not production regression helpers.
"""
import argparse
import difflib
from fractions import Fraction as F
import hashlib
import json
import math
from pathlib import Path
import subprocess


def reference(source):
    rows = [line.split() for line in source.split("datalines;", 1)[1].split(";", 1)[0].splitlines() if line.strip()]
    groups = {}
    for row in rows:
        groups.setdefault(row[3], []).append((F(row[0]), F(row[2])))
    assert len(groups) == 2
    levels = sorted(groups)
    means = {g: (sum(x for x, y in values) / len(values), sum(y for x, y in values) / len(values)) for g, values in groups.items()}
    sxx = sum((x - means[g][0])**2 for g, values in groups.items() for x, y in values)
    sxy = sum((x - means[g][0]) * (y - means[g][1]) for g, values in groups.items() for x, y in values)
    slope = sxy / sxx
    sse = sum((y - means[g][1] - slope*(x - means[g][0]))**2 for g, values in groups.items() for x, y in values)
    df = len(rows) - len(levels) - 1
    low, high = levels
    dx = means[high][0] - means[low][0]
    estimate = means[high][1] - means[low][1] - slope*dx
    factor = F(1, len(groups[low])) + F(1, len(groups[high])) + dx**2 / sxx
    variance = factor * sse / df
    t = float(estimate) / math.sqrt(float(variance))
    # Independent t tail via the elementary cosine-power integral for odd df.
    assert df % 2 == 1
    def integral(theta):
        value = theta
        for power in range(2, df, 2):
            value = math.sin(theta)*math.cos(theta)**(power-1)/power + (power-1)*value/power
        return value
    p = 1 - integral(math.atan(abs(t)/math.sqrt(df))) / integral(math.pi/2)
    return {"estimate": estimate, "variance_factor": factor, "variance": variance,
            "slope": slope, "error_ss": sse, "df_error": df, "t": t, "p": p}


def main():
    folder = Path(__file__).resolve().parent
    repo = folder.parents[2]
    parser = argparse.ArgumentParser()
    parser.add_argument("--exe", type=Path, default=repo / "zig-out/bin/opensas")
    parser.add_argument("--out", type=Path, default=repo / ".zig-cache/stat-common-025-evidence")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    source = folder / "estimate_coefficients.sas"
    expected_file = folder / "estimate_coefficients.expected.txt"
    expected = expected_file.read_text()
    result = subprocess.run([str(args.exe.resolve()), str(source)], cwd=args.out, capture_output=True, text=True)
    (args.out / "actual.txt").write_text(result.stdout)
    (args.out / "actual.log").write_text(result.stderr)
    (args.out / "actual.rc").write_text(str(result.returncode) + "\n")
    et, at = expected.split(), result.stdout.split()
    diff = "\n".join(difflib.unified_diff(et, at, fromfile="SAS", tofile="OpenSAS", lineterm=""))
    (args.out / "raw-token.diff").write_text(diff)
    assert result.returncode == int((folder / "estimate_coefficients.expected.rc").read_text()), result.stderr
    assert et == at, diff
    ref = reference(source.read_text())
    for text in (expected, result.stdout):
        tokens = text.split()
        values = tokens[-4:]
        assert abs(F(values[0]) - ref["estimate"]) <= F(1, 2*10**8)
        assert abs(float(values[1]) - math.sqrt(float(ref["variance"]))) <= 0.5e-8
        assert abs(float(values[2]) - ref["t"]) <= 0.005
        assert abs(float(values[3]) - ref["p"]) <= 0.00005
    report = {"status": "pass", "exit_status": result.returncode,
              "expected_tokens": len(et), "actual_tokens": len(at), "raw_token_differences": 0,
              "normalization": "whitespace only", "stderr_bytes": len(result.stderr.encode()),
              "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
              "expected_sha256": hashlib.sha256(expected_file.read_bytes()).hexdigest(),
              "independent_ancova": {k: str(v) for k, v in ref.items()}}
    (args.out / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
