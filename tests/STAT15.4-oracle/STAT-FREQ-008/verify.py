"""Full oracle replay and independent conditional-proportion orientation/CI checks."""
import argparse
from decimal import Decimal, localcontext
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import re
from statistics import NormalDist
import subprocess
import xml.etree.ElementTree as ET


def reference(cells, alpha):
    a, b, c, d = cells
    definitions = (("Sensitivity", a, a + c), ("Specificity", d, b + d),
                   ("Positive Predictive Value", a, a + b), ("Negative Predictive Value", d, c + d))
    result = {}
    with localcontext() as context:
        context.prec = 60
        critical = Decimal(str(NormalDist().inv_cdf(1 - alpha / 2)))
        for name, success, total in definitions:
            assert total > 0
            proportion = Fraction(success, total)
            variance = proportion * (1 - proportion) / total
            p = Decimal(proportion.numerator) / proportion.denominator
            se = (Decimal(variance.numerator) / variance.denominator).sqrt()
            lower, upper = max(Decimal(0), p - critical * se), min(Decimal(1), p + critical * se)
            result[name] = {"success": success, "conditional_n": total,
                "proportion_exact": str(proportion), "variance_exact": str(variance),
                "unrounded": [str(x) for x in (p, se, lower, upper)],
                "printed": [f"{x:.4f}" for x in (p, se, lower, upper)]}
    return result


def check_metrics(output, cells, alpha):
    rows = [line.split() for line in output.decode().splitlines()]
    expected = reference(cells, alpha)
    for name, values in expected.items():
        matching = [row for row in rows if row[:-4] == name.split()]
        assert len(matching) == 1, (name, matching)
        assert matching[0][-4:] == values["printed"], (name, matching, values)
    assert ["Sample", "Size", "=", str(sum(cells))] in rows
    assert any(f"{100 * (1-alpha):g}%" in row for row in rows)
    return expected


def main():
    ticket = Path(__file__).resolve().parent
    repo = ticket.parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=repo / "zig-out/bin/opensas")
    parser.add_argument("--output", type=Path, default=ticket / "dev3-results")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    sha = lambda data: hashlib.sha256(data).hexdigest()
    manifest = {"normalization": "whitespace runs/edges only", "runs": {}, "formula_checks": {}}

    def execute(source, name, graph_dir=None):
        command = [str(args.binary)] + (["--graphics-dir", str(graph_dir)] if graph_dir else []) + [str(source)]
        result = subprocess.run(command, cwd=repo, capture_output=True)
        for suffix, data in (("txt", result.stdout), ("log", result.stderr), ("rc", f"{result.returncode}\n".encode())):
            (args.output / f"{name}.actual.{suffix}").write_bytes(data)
        assert result.returncode == 0, (name, result.stderr)
        manifest["runs"][name] = {"input_sha256": sha(source.read_bytes()), "actual_sha256": sha(result.stdout),
            "stderr_sha256": sha(result.stderr), "status": result.returncode, "diagnostics": result.stderr.decode().splitlines()}
        return result

    source = ticket / "documented_feature.sas"
    graphs = args.output / "graphs"
    graphs.mkdir(exist_ok=True)
    assert not list(graphs.iterdir()), "Use a fresh output directory"
    original = execute(source, "documented_feature", graphs)
    expected = source.with_suffix(".expected.txt").read_bytes()
    assert int(source.with_suffix(".expected.rc").read_text()) == 0
    assert original.stdout.split() == expected.split()
    severities = lambda b: re.findall(rb"^(?:ERROR|WARNING)[^\n]*", b, re.M)
    assert severities(original.stderr) == severities(source.with_suffix(".oracle.log").read_bytes()) == []
    manifest["runs"]["documented_feature"].update(expected_sha256=sha(expected), full_token_match=True, tokens=len(expected.split()))

    # Original data order intentionally puts the positive levels first. Default
    # internal sorting instead puts 'negative' first; this must change the targets.
    cases = [
        ("positive_first", [12, 8, 5, 25], "order=data", "TestResult*Condition", [12, 8, 5, 25], .05),
        ("transpose", [12, 8, 5, 25], "order=data", "Condition*TestResult", [12, 5, 8, 25], .05),
        ("negative_first_default", [12, 8, 5, 25], "", "TestResult*Condition", [25, 5, 8, 12], .05),
        ("confidence_90", [12, 8, 5, 25], "order=data", "TestResult*Condition", [12, 8, 5, 25], .1),
        ("perfect", [5, 0, 0, 7], "order=data", "TestResult*Condition", [5, 0, 0, 7], .05),
        ("all_incorrect", [0, 4, 6, 0], "order=data", "TestResult*Condition", [0, 4, 6, 0], .05),
    ]
    for name, cells, order, variables, ordered_cells, alpha in cases:
        program = args.output / (name + ".sas")
        data = "\n".join(f"{row} {col} {count}" for (row, col), count in zip(
            (("positive", "positive"), ("positive", "negative"), ("negative", "positive"), ("negative", "negative")), cells))
        level = "" if alpha == .05 else f"alpha={alpha}"
        program.write_text(f"options nodate nonumber; ods graphics off;\ndata d; input TestResult $ Condition $ Count; datalines;\n{data}\n;\nproc freq data=d {order}; weight Count / zeros; tables {variables} / noprint senspec {level}; run;\n")
        result = execute(program.resolve(), name)
        assert result.stderr == b""
        manifest["formula_checks"][name] = {"ordered_cells": ordered_cells, "alpha": alpha,
                                             "metrics": check_metrics(result.stdout, ordered_cells, alpha)}

    for name in ("freq_risk_twoway_public", "freq_risk_strata_public"):
        program = repo / "tests/corpus" / (name + ".sas")
        result = execute(program, name)
        expected = program.with_suffix(".txt").read_bytes()
        assert result.stdout.split() == expected.split()
        manifest["runs"][name].update(expected_sha256=sha(expected), full_token_match=True)

    svg_files = sorted(graphs.glob("*.svg"))
    assert len(svg_files) == 3
    ns = {"s": "http://www.w3.org/2000/svg"}
    for path, counts in zip(svg_files[:2], ([27, 29, 14, 35], [23, 10, 53, 32])):
        root = ET.fromstring(path.read_bytes())
        assert [int(node.attrib["data-count"]) for node in root.findall(".//s:rect[@class='bar']", ns)] == counts
    assert ET.fromstring(svg_files[2].read_bytes()).attrib["data-kind"] == "agreeplot"
    manifest["graphics_sha256"] = {path.name: sha(path.read_bytes()) for path in svg_files}
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("PASS: original full oracle; all four metrics/SEs/CIs in six orientation/alpha/boundary cases; existing goldens and graphs")


if __name__ == "__main__":
    main()
