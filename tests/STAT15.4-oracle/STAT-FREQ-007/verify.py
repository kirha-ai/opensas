"""Full unchanged replay plus independent binomial sums, intervals and boundary checks."""
import argparse
from decimal import Decimal, localcontext
import hashlib
import json
import math
from pathlib import Path
import re
from statistics import NormalDist
import subprocess


def reference(x, n, alpha, p0):
    p = x / n
    z = NormalDist().inv_cdf(1 - alpha / 2)
    se = math.sqrt(p * (1 - p) / n)
    null_se = math.sqrt(p0 * (1 - p0) / n)
    statistic = (p - p0) / null_se
    tail = math.erfc(abs(statistic) / math.sqrt(2)) / 2
    adjusted_n = n + z * z
    adjusted_p = (x + z * z / 2) / adjusted_n
    ac_width = z * math.sqrt(adjusted_p * (1 - adjusted_p) / adjusted_n)
    center = (p + z * z / (2 * n)) / (1 + z * z / n)
    width = z * math.sqrt((p * (1 - p) + z * z / (4 * n)) / n) / (1 + z * z / n)
    with localcontext() as context:
        context.prec = 50
        def cdf(k, probability):
            q = 1 - probability
            term = q ** n
            total = term
            for i in range(k):
                term = term * (n - i) * probability / ((i + 1) * q)
                total += term
            return total
        def invert(k, target):
            lo, hi = Decimal(0), Decimal(1)
            for _ in range(150):
                mid = (lo + hi) / 2
                if cdf(k, mid) > target:
                    lo = mid
                else:
                    hi = mid
            return float((lo + hi) / 2)
        half = Decimal(str(alpha)) / 2
        exact = [0.0 if x == 0 else invert(x - 1, 1 - half),
                 1.0 if x == n else invert(x, half)]
    return {"success": x, "total": n, "alpha": alpha, "null": p0,
            "proportion": p, "ase": se, "null_se": null_se, "z": statistic,
            "one_sided": tail, "two_sided": 2 * tail,
            "limits": {"Agresti-Coull": [max(0, adjusted_p - ac_width), min(1, adjusted_p + ac_width)],
                       "Clopper-Pearson (Exact)": exact,
                       "Wilson": [max(0, center - width), min(1, center + width)],
                       "Wald": [max(0, p - z * se), min(1, p + z * se)]}}


def main():
    ticket = Path(__file__).resolve().parent
    repo = ticket.parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=repo / "zig-out/bin/opensas")
    parser.add_argument("--output", type=Path, default=ticket / "dev3-results")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    sha = lambda data: hashlib.sha256(data).hexdigest()
    def run(source, stem):
        result = subprocess.run([str(args.binary), str(source)], cwd=repo, capture_output=True)
        for suffix, data in (("txt", result.stdout), ("log", result.stderr), ("rc", f"{result.returncode}\n".encode())):
            (args.output / f"{stem}.actual.{suffix}").write_bytes(data)
        assert result.returncode == 0 and result.stderr == b""
        return result.stdout
    source = ticket / "documented_feature.sas"
    actual = run(source, "documented_feature")
    expected = source.with_suffix(".expected.txt").read_bytes()
    assert int(source.with_suffix(".expected.rc").read_text()) == 0
    assert re.findall(rb"^(?:ERROR|WARNING)[^\n]*", source.with_suffix(".oracle.log").read_bytes(), re.M) == []
    assert actual.split() == expected.split()
    eyes = reference(341, 762, .1, .5)
    hair = reference(228, 762, .05, .28)
    fmt = lambda x: f"{x:.4f}"
    probability = lambda p: "<.0001" if p < .0001 else fmt(p)
    rows = [line.split() for line in actual.decode().splitlines()]
    for method in ("Agresti-Coull", "Clopper-Pearson (Exact)", "Wilson"):
        assert method.split() + [fmt(v) for v in eyes["limits"][method]] in rows
    for ref in (eyes, hair):
        for label, value in (("Proportion", ref["proportion"]), ("ASE", ref["ase"]), ("ASE under H0", ref["null_se"]), ("Z", ref["z"])):
            assert label.split() + [fmt(value)] in rows
        assert ["Two-sided", "Pr", ">", "|Z|", probability(ref["two_sided"])] in rows
        assert ["One-sided", "Pr", ">" if ref["z"] > 0 else "<", "Z", probability(ref["one_sided"])] in rows
    for method in ("Wald", "Clopper-Pearson (Exact)"):
        for label, value in zip(("Lower", "Upper"), hair["limits"][method]):
            assert ["95%", label, "Conf", "Limit", fmt(value)] in rows
    lower, upper = .28 - .1, .28 + .1
    zl, zu = (hair["proportion"] - lower) / hair["ase"], (hair["proportion"] - upper) / hair["ase"]
    pl, pu = math.erfc(zl / math.sqrt(2)) / 2, math.erfc(-zu / math.sqrt(2)) / 2
    critical = NormalDist().inv_cdf(.95)
    ci = [hair["proportion"] - critical * hair["ase"], hair["proportion"] + critical * hair["ase"]]
    assert ["Lower", "Margin", fmt(zl), "Pr", ">", "Z", probability(pl)] in rows
    assert ["Upper", "Margin", fmt(zu), "Pr", "<", "Z", probability(pu)] in rows
    assert ["Overall", probability(max(pl, pu))] in rows
    assert [fmt(lower), fmt(upper), *map(fmt, ci)] in rows
    manifest = {"input_sha256": sha(source.read_bytes()), "expected_sha256": sha(expected),
                "actual_sha256": sha(actual), "stderr_sha256": sha(b""), "status": 0,
                "tokens": len(actual.split()), "normalization": "whitespace only", "eyes": eyes, "hair": hair,
                "equivalence": {"lower_z": zl, "upper_z": zu, "lower_p": pl, "upper_p": pu, "overall_p": max(pl, pu), "confidence_limits": ci}, "boundaries": []}
    # Valid boundary samples retain the zero-frequency event with WEIGHT/ZEROS.
    for index, (x, n, p0) in enumerate(((0, 10, .5), (10, 10, .5), (2, 10, .3), (0, 10, .99), (10, 10, .01))):
        program = args.output / f"boundary-{index}.sas"
        program.write_text(f"options nodate nonumber; ods graphics off;\ndata d;input event count;datalines;\n1 {x}\n2 {n-x}\n;\nproc freq data=d;weight count / zeros;tables event / noprint binomial(p={p0} cl=(ac exact wald wilson));run;\n")
        output = run(program.resolve(), f"boundary-{index}")
        ref = reference(x, n, .05, p0)
        observed_rows = [line.split() for line in output.decode().splitlines()]
        assert ["Proportion", fmt(ref["proportion"])] in observed_rows
        assert ["ASE", fmt(ref["ase"])] in observed_rows
        for method, limits in ref["limits"].items():
            assert method.split() + [fmt(v) for v in limits] in observed_rows, (x, method, limits)
        assert ["Z", fmt(ref["z"])] in observed_rows
        assert ["Two-sided", "Pr", ">", "|Z|", probability(ref["two_sided"])] in observed_rows
        ref["actual_sha256"] = sha(output)
        manifest["boundaries"].append(ref)
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("PASS: complete oracle; independently inverted exact limits, Wald/AC/Wilson, equality/TOST, and five boundary samples")


if __name__ == "__main__":
    main()
