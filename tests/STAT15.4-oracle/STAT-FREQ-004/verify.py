"""Replay every README oracle unchanged; retain raw results and a compact manifest."""
import argparse
from decimal import Decimal, localcontext
import difflib
from fractions import Fraction
import hashlib
import json
from math import comb
from pathlib import Path
import re
import subprocess


def sha(data):
    return hashlib.sha256(data).hexdigest()


def normalized(data):
    return " ".join(data.decode().split()).encode()


def independent_checks():
    # Enumerate labeled allocations directly, independently of OpenSAS routines.
    def distribution(r1, r2, c1):
        n = r1 + r2
        xs = list(range(max(0, c1 - r2), min(r1, c1) + 1))
        weights = [comb(c1, x) * comb(n - c1, r1 - x) for x in xs]
        den = comb(n, r1)
        assert sum(weights) == den
        return xs, weights, [Fraction(w, den) for w in weights], den

    xs, weights, mass, den = distribution(15, 8, 13)
    observed = xs.index(11)
    chi = lambda x: Fraction(23 * (23 * x - 15 * 13) ** 2, 15 * 8 * 13 * 10)
    fisher = sum(p for p in mass if p <= mass[observed])
    pearson = sum(p for x, p in zip(xs, mass) if chi(x) >= chi(11))
    assert fisher == pearson == Fraction(292, 7429)
    with localcontext() as context:
        context.prec = 70

        def tail(theta, right):
            terms = [Decimal(w) * theta ** (x - xs[0]) for x, w in zip(xs, weights)]
            selected = sum(p for x, p in zip(xs, terms) if (x >= 11 if right else x <= 11))
            return selected / sum(terms)

        def endpoint(right):
            lo, hi, target = Decimal(0), Decimal(1), Decimal(".025")
            while (tail(hi, right) < target if right else tail(hi, right) > target):
                hi *= 2
            for _ in range(230):
                mid = (lo + hi) / 2
                if (tail(mid, right) < target if right else tail(mid, right) > target):
                    lo = mid
                else:
                    hi = mid
            return str(round((lo + hi) / 2, 12))

        limits = [endpoint(True), endpoint(False)]
    assert [f"{float(x):.4f}" for x in limits] == ["0.8677", "105.5488"]
    zx, zw, zm, zd = distribution(5, 5, 5)
    tied = sum(p for p in zm if p == zm[0])
    assert tied == Fraction(1, 126)
    dx, dw, dm, dd = distribution(0, 3, 1)
    assert dm == [Fraction(1)]
    multinomial = [Fraction(comb(10, x) * 3 ** x * 7 ** (10 - x), 10 ** 10) for x in range(11)]
    gof = sum(p for x, p in enumerate(multinomial) if abs(x - 3) >= 1)
    assert f"{float(gof):.4f}" == "0.7332"
    return {
        "FatComp": {"support": xs, "integer_weights": weights, "denominator": den,
                    "point": str(mass[observed]), "left": str(sum(mass[:observed + 1])),
                    "right": str(sum(mass[observed:])), "fisher_two_sided": str(fisher),
                    "pearson_exact": str(pearson), "odds_limits_95": limits},
        "zero_cells_and_ties": {"cells": [0, 5, 5, 0], "support": zx,
                                "weights": zw, "denominator": zd, "tied_point_mass": str(tied)},
        "degenerate_support": {"cells": [0, 0, 1, 2], "support": dx,
                               "weights": dw, "denominator": dd, "mass": [str(p) for p in dm]},
        "one_way": {"counts": [2, 8], "null": ["3/10", "7/10"], "pearson_exact": str(gof)},
    }


def main():
    ticket = Path(__file__).resolve().parent
    repo = ticket.parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=repo / "zig-out/bin/opensas")
    parser.add_argument("--output", type=Path, default=ticket / "dev3-results")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    names = re.findall(r"\[[^\]]+\.sas\]\(([^)]+\.sas)\)", (ticket / "README.md").read_text())
    assert names, "README lists no SAS programs"
    manifest = {"normalization": "collapse whitespace runs and trim edges only", "cases": {},
                "independent_enumeration": independent_checks()}
    good = True
    for name in names:
        source = ticket / name
        stem = source.stem
        expected = source.with_suffix(".expected.txt").read_bytes()
        expected_status = int(source.with_suffix(".expected.rc").read_text())
        reference_log = source.with_suffix(".oracle.log").read_bytes()
        graph_dir = args.output / (stem + "-graphs")
        graph_dir.mkdir(exist_ok=True)
        assert not list(graph_dir.iterdir()), "Use a fresh output directory for each replay"
        run = subprocess.run([str(args.binary), "--graphics-dir", str(graph_dir),
                              str(source.relative_to(repo))], cwd=repo, capture_output=True)
        for suffix, data in (("txt", run.stdout), ("log", run.stderr), ("rc", f"{run.returncode}\n".encode())):
            (args.output / f"{stem}.actual.{suffix}").write_bytes(data)
        diagnostic_lines = lambda b: re.findall(rb"^(?:ERROR|WARNING)[^\n]*", b, re.M)
        actual_diagnostics = diagnostic_lines(run.stderr)
        reference_diagnostics = diagnostic_lines(reference_log)
        match = normalized(run.stdout) == normalized(expected)
        good &= match and run.returncode == expected_status and actual_diagnostics == reference_diagnostics
        if not match:
            diff = difflib.unified_diff(expected.decode().splitlines(True), run.stdout.decode().splitlines(True),
                                        fromfile="expected", tofile="actual")
            (args.output / f"{stem}.diff").write_text("".join(diff))
        manifest["cases"][name] = {
            "input_sha256": sha(source.read_bytes()), "expected_sha256": sha(expected),
            "actual_sha256": sha(run.stdout), "actual_stderr_sha256": sha(run.stderr),
            "normalized_sha256": sha(normalized(run.stdout)), "tokens": len(run.stdout.split()),
            "expected_status": expected_status, "actual_status": run.returncode, "full_text_match": match,
            "reference_warning_errors": [s.decode() for s in reference_diagnostics],
            "actual_warning_errors": [s.decode() for s in actual_diagnostics],
            "graphics": sorted(p.name for p in graph_dir.iterdir()),
        }
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({name: {"text": case["full_text_match"], "status": case["actual_status"],
                            "tokens": case["tokens"]} for name, case in manifest["cases"].items()}))
    raise SystemExit(0 if good else 1)


if __name__ == "__main__":
    main()
