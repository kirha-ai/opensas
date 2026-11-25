"""Independent multinomial delta-method checks and complete unchanged oracle replay."""
import argparse
from decimal import Decimal, localcontext
import hashlib
import json
import math
from pathlib import Path
import re
from statistics import NormalDist
import subprocess
import xml.etree.ElementTree as ET


class D:
    """Decimal value and exact forward derivatives in the nine cell counts."""
    def __init__(self, value, gradient=None):
        self.v = Decimal(value)
        self.g = gradient if gradient is not None else [Decimal(0)] * 9

    @staticmethod
    def cast(x):
        return x if isinstance(x, D) else D(x)

    def __add__(self, other):
        other = D.cast(other)
        return D(self.v + other.v, [a + b for a, b in zip(self.g, other.g)])

    __radd__ = __add__

    def __neg__(self):
        return D(-self.v, [-g for g in self.g])

    def __sub__(self, other):
        return self + -D.cast(other)

    def __rsub__(self, other):
        return D.cast(other) - self

    def __mul__(self, other):
        other = D.cast(other)
        return D(self.v * other.v, [a * other.v + self.v * b for a, b in zip(self.g, other.g)])

    __rmul__ = __mul__

    def __truediv__(self, other):
        other = D.cast(other)
        return D(self.v / other.v, [(a * other.v - self.v * b) / (other.v * other.v) for a, b in zip(self.g, other.g)])

    def sqrt(self):
        root = self.v.sqrt()
        return D(root, [g / (2 * root) for g in self.g])

    def log(self):
        return D(self.v.ln(), [g / self.v for g in self.g])


def references():
    counts = [12, 5, 3, 4, 17, 6, 2, 8, 13]
    cells = [D(n, [Decimal(i == j) for j in range(9)]) for i, n in enumerate(counts)]
    total = sum(cells)
    rows = [sum(cells[i * 3:i * 3 + 3]) for i in range(3)]
    cols = [sum(cells[j::3]) for j in range(3)]
    concordant, discordant = D(0), D(0)
    for i, x in enumerate(cells):
        for j, y in enumerate(cells):
            direction = (i // 3 - j // 3) * (i % 3 - j % 3)
            if direction > 0:
                concordant += x * y
            elif direction < 0:
                discordant += x * y
    delta = concordant - discordant
    wr = total * total - sum(x * x for x in rows)
    wc = total * total - sum(x * x for x in cols)
    measures = {}
    numerators = {}

    def ratio(name, numerator, denominator, tested=True):
        measures[name] = numerator / denominator
        if tested:
            numerators[name] = (numerator, denominator.v)

    ratio("Gamma", delta, concordant + discordant)
    ratio("Kendall's Tau-b", delta, (wr * wc).sqrt())
    ratio("Stuart's Tau-c", 3 * delta, 2 * total * total)
    ratio("Somers' D C|R", delta, wr)
    ratio("Somers' D R|C", delta, wc)
    mean_r = sum((i + 1) * x for i, x in enumerate(rows)) / total
    mean_c = sum((i + 1) * x for i, x in enumerate(cols)) / total
    fixed_r = [i + 1 - mean_r for i in range(3)]
    fixed_c = [i + 1 - mean_c for i in range(3)]
    rank_r = [sum(rows[:i]) + rows[i] / 2 - total / 2 for i in range(3)]
    rank_c = [sum(cols[:i]) + cols[i] / 2 - total / 2 for i in range(3)]
    for name, rs, cs in (("Pearson Correlation", fixed_r, fixed_c), ("Spearman Correlation", rank_r, rank_c)):
        covariance = sum(x * rs[i // 3] * cs[i % 3] for i, x in enumerate(cells))
        sr = sum(x * score * score for x, score in zip(rows, rs))
        sc = sum(x * score * score for x, score in zip(cols, cs))
        ratio(name, covariance, (sr * sc).sqrt())
    # Every maximum in this sample is unique, avoiding a nondifferentiable tie.
    maximum = lambda xs: max(xs, key=lambda x: x.v)
    row_modes = sum(maximum(cells[i * 3:i * 3 + 3]) for i in range(3))
    col_modes = sum(maximum(cells[j::3]) for j in range(3))
    max_row, max_col = maximum(rows), maximum(cols)
    ratio("Lambda Asymmetric C|R", row_modes - max_col, total - max_col, False)
    ratio("Lambda Asymmetric R|C", col_modes - max_row, total - max_row, False)
    ratio("Lambda Symmetric", row_modes + col_modes - max_row - max_col, 2 * total - max_row - max_col, False)
    entropy = lambda xs: -sum((x / total) * (x / total).log() for x in xs)
    hx, hy, hxy = entropy(rows), entropy(cols), entropy(cells)
    information = hx + hy - hxy
    ratio("Uncertainty Coefficient C|R", information, hy, False)
    ratio("Uncertainty Coefficient R|C", information, hx, False)
    ratio("Uncertainty Coefficient Symmetric", 2 * information, hx + hy, False)

    def variance(gradient):
        # Cov(N_i,N_j) = diag(n_i) - n_i*n_j/N; no engine variance routines.
        mean = sum(n * g for n, g in zip(counts, gradient))
        result = sum(n * g * g for n, g in zip(counts, gradient)) - mean * mean / total.v
        assert result >= 0
        return result

    critical = Decimal(str(NormalDist().inv_cdf(0.975)))
    results = {}
    for name, estimate in measures.items():
        ase = variance(estimate.g).sqrt()
        lower, upper = estimate.v - critical * ase, estimate.v + critical * ase
        result = {"reference": [str(x) for x in (estimate.v, ase, lower, upper)],
                  "printed": [f"{x:.4f}" for x in (estimate.v, ase, lower, upper)]}
        if name in numerators:
            numerator, denominator = numerators[name]
            null_se = (variance(numerator.g) / (denominator * denominator)).sqrt()
            z = estimate.v / null_se
            two_sided = math.erfc(abs(float(z)) / math.sqrt(2))
            probability = lambda p: "<.0001" if p < 0.0001 else f"{p:.4f}"
            result["test"] = {"null_se": str(null_se), "z": str(z), "two_sided": repr(two_sided),
                              "printed": [f"{null_se:.4f}", f"{z:.4f}", probability(two_sided / 2), probability(two_sided)]}
        results[name] = result
    return {"counts": counts, "N": str(total.v), "P": str(concordant.v), "Q": str(discordant.v), "measures": results}


def main():
    ticket = Path(__file__).resolve().parent
    repo = ticket.parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=repo / "zig-out/bin/opensas")
    parser.add_argument("--output", type=Path, default=ticket / "dev3-results")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    graph_dir = args.output / "graphs"
    graph_dir.mkdir(exist_ok=True)
    assert not list(graph_dir.iterdir()), "Use a fresh output directory"
    sha = lambda data: hashlib.sha256(data).hexdigest()
    manifest = {"normalization": "whitespace runs/edges only", "runs": {}}
    runs = [(ticket / "documented_feature.sas", True),
            (repo / "tests/corpus/freq_tests_association.sas", False),
            (repo / "tests/corpus/freq_tests_edges.sas", False)]
    outputs = {}
    for source, oracle in runs:
        command = [str(args.binary)] + (["--graphics-dir", str(graph_dir)] if oracle else []) + [str(source.relative_to(repo))]
        run = subprocess.run(command, cwd=repo, capture_output=True)
        expected = source.with_suffix(".expected.txt" if oracle else ".txt").read_bytes()
        for ext, data in (("txt", run.stdout), ("log", run.stderr), ("rc", f"{run.returncode}\n".encode())):
            (args.output / (source.stem + ".actual." + ext)).write_bytes(data)
        assert run.returncode == 0
        assert run.stdout.split() == expected.split(), source.name
        if oracle:
            severity = lambda b: re.findall(rb"^(?:ERROR|WARNING)[^\n]*", b, re.M)
            assert severity(run.stderr) == severity(source.with_suffix(".oracle.log").read_bytes()) == []
        manifest["runs"][source.name] = {"input_sha256": sha(source.read_bytes()), "expected_sha256": sha(expected),
            "actual_sha256": sha(run.stdout), "stderr_sha256": sha(run.stderr), "status": run.returncode,
            "full_token_match": True, "tokens": len(run.stdout.split()), "diagnostics": run.stderr.decode().splitlines()}
        outputs[source.stem] = run.stdout.decode()
    with localcontext() as context:
        context.prec = 60
        reference = references()
    listing = outputs["freq_tests_association"]
    rows = [line.split() for line in listing.splitlines()]
    for name, result in reference["measures"].items():
        row = next(row for row in rows if row[:-4] == name.split())
        assert row[-4:] == result["printed"], (name, row, result["printed"])
        if "test" in result:
            start = listing.index("Test of H0: " + name + " = 0")
            block = listing[start:].split("\n\n", 2)[1]
            fields = [line.split() for line in block.splitlines() if line.strip()]
            assert [row[-1] for row in fields] == result["test"]["printed"], (name, fields)
    boundary = outputs["freq_tests_edges"].rsplit("Statistics for Table of r by c", 1)[1]
    assert "Row or column sum zero. No statistics computed for this table." in boundary
    assert "Gamma" not in boundary and "Sample Size = 13" in boundary
    svg_files = sorted(graph_dir.glob("*.svg"))
    assert len(svg_files) == 3
    ns = {"s": "http://www.w3.org/2000/svg"}
    for path, counts in zip(svg_files[:2], ([27, 29, 14, 35], [23, 10, 53, 32])):
        root = ET.fromstring(path.read_bytes())
        assert [int(node.attrib["data-count"]) for node in root.findall(".//s:rect[@class='bar']", ns)] == counts
    assert ET.fromstring(svg_files[2].read_bytes()).attrib["data-kind"] == "agreeplot"
    manifest["independent_multinomial_checks"] = reference
    manifest["graphics_sha256"] = {f.name: sha(f.read_bytes()) for f in svg_files}
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("PASS: own full oracle, 13 independent estimate/ASE/CI rows, seven null-SE/Z/tail tests, zero-margin status and graphs")


if __name__ == "__main__":
    main()
