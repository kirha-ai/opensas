"""Replay the unchanged oracle and preserve exact counts, printed values and SVG residuals."""
import argparse
from collections import defaultdict
from decimal import Decimal, localcontext
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET


def sha(data):
    return hashlib.sha256(data).hexdigest()


def dec(value):
    return Decimal(value.numerator) / Decimal(value.denominator)


def main():
    ticket = Path(__file__).resolve().parent
    repo = ticket.parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=repo / "zig-out/bin/opensas")
    parser.add_argument("--output", type=Path, default=ticket / "dev3-results")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    graphs = args.output / "graphs"
    graphs.mkdir(exist_ok=True)
    assert not list(graphs.iterdir()), "Use a fresh output directory"
    source = ticket / "documented_feature.sas"
    expected = source.with_suffix(".expected.txt").read_bytes()
    run = subprocess.run([str(args.binary), "--graphics-dir", str(graphs),
                          str(source.relative_to(repo))], cwd=repo, capture_output=True)
    for suffix, data in (("txt", run.stdout), ("log", run.stderr), ("rc", f"{run.returncode}\n".encode())):
        (args.output / ("actual." + suffix)).write_bytes(data)
    assert run.returncode == int(source.with_suffix(".expected.rc").read_text()) == 0
    assert run.stdout.split() == expected.split(), "Complete listing differs; no numerical tolerance applied"
    severity = lambda data: re.findall(rb"^(?:ERROR|WARNING)[^\n]*", data, re.M)
    assert severity(run.stderr) == severity(source.with_suffix(".oracle.log").read_bytes()) == []
    # Independently aggregate the original 27 input records, preserving DATA order.
    data = source.read_text().split("datalines;", 1)[1].split(";", 1)[0].split()
    assert len(data) == 27 * 4
    counts = defaultdict(lambda: defaultdict(int))
    for i in range(0, len(data), 4):
        region, eyes, hair, count = data[i:i + 4]
        counts[int(region)][hair] += int(count)
    proportions = [Fraction(x, 100) for x in (30, 12, 30, 25, 3)]
    manifest = {"input_sha256": sha(source.read_bytes()), "expected_sha256": sha(expected),
                "actual_sha256": sha(run.stdout), "stderr_sha256": sha(run.stderr),
                "full_token_match": True, "tokens": len(expected.split()), "status": run.returncode,
                "normalization": "whitespace runs and edges only", "warning_errors": [], "groups": {}}
    svg_files = sorted(graphs.glob("*.svg"))
    assert len(svg_files) == 2
    ns = {"s": "http://www.w3.org/2000/svg"}
    with localcontext() as context:
        context.prec = 60
        for (region, cells), svg_file in zip(sorted(counts.items()), svg_files):
            observed = list(cells.values())
            total = sum(observed)
            null_counts = [total * p for p in proportions]
            chi = sum((o - e) ** 2 / e for o, e in zip(observed, null_counts))
            x = dec(chi)
            # Closed-form chi-square survival function for df=4, independent of OpenSAS.
            probability = (-x / 2).exp() * (1 + x / 2)
            printed = [f"{x:.4f}", f"{probability:.4f}"]
            assert printed == (["7.7602", "0.1008"] if region == 1 else ["21.3824", "0.0003"])
            xml = ET.fromstring(svg_file.read_bytes())
            assert xml.attrib["data-kind"] == "deviationplot"
            texts = [t.text or "" for t in xml.findall(".//s:text", ns)]
            assert f"Geographic Region={region}" in texts
            assert any(" ".join(t.split()) == "Pr > ChiSq " + printed[1] for t in texts)
            axes = xml.find(".//s:g[@class='axes']", ns)
            ticks = [Decimal(t.text) for t in axes.findall("s:text", ns)]
            left, _, _, width = map(Decimal, re.fullmatch(r"M([\d.]+) ([\d.]+)v([\d.]+)h([\d.]+)", axes.find("s:path", ns).attrib["d"]).groups())
            dots = xml.findall(".//s:circle[@class='dot']", ns)
            assert len(dots) == 5
            residuals = []
            for (name, count), null_count, dot in zip(cells.items(), null_counts, dots):
                relative = (count - null_count) / null_count
                actual = Decimal(dot.attrib["data-value"])
                assert Decimal(dot.attrib["data-count"]) == count
                coordinate = left + width * (dec(relative) - ticks[0]) / (ticks[-1] - ticks[0])
                assert f"{coordinate:.2f}" == dot.attrib["cx"], "Plotted position differs at SVG's two-decimal precision"
                residuals.append({"level": name, "exact_relative_deviation": str(relative),
                                  "actual_data_value": str(actual), "decimal_difference": str(actual - dec(relative)),
                                  "cx": dot.attrib["cx"]})
            manifest["groups"][region] = {"counts": observed, "total": total,
                "expected_counts": [str(e) for e in null_counts], "pearson_exact": str(chi),
                "pearson_decimal": str(x), "df": 4, "probability_decimal": str(probability),
                "printed_statistic_probability": printed, "svg_sha256": sha(svg_file.read_bytes()),
                "plot_residuals": residuals}
    # Independent two-way formulas checked against the existing public regression.
    fixture = repo / "tests/corpus/freq_tests_association.sas"
    small = subprocess.run([str(args.binary), str(fixture.relative_to(repo))], cwd=repo, capture_output=True)
    (args.output / "association.actual.txt").write_bytes(small.stdout)
    (args.output / "association.actual.log").write_bytes(small.stderr)
    assert small.returncode == 0
    assert small.stdout.split() == fixture.with_suffix(".txt").read_bytes().split()
    observed, null_counts = [1, 9, 11, 3], [5, 5, 7, 7]
    pearson = sum(Fraction((o - e) ** 2, e) for o, e in zip(observed, null_counts))
    corrected = sum(max(Fraction(0), abs(Fraction(o - e)) - Fraction(1, 2)) ** 2 / e for o, e in zip(observed, null_counts))
    likelihood = 2 * sum(o * math.log(o / e) for o, e in zip(observed, null_counts))
    mh = Fraction(23, 24) * pearson
    rows = [line.split() for line in small.stdout.decode().splitlines()]
    stats = {}
    for label, value in (("Chi-Square", pearson), ("Likelihood Ratio Chi-Square", likelihood),
                         ("Continuity Adj. Chi-Square", corrected), ("Mantel-Haenszel Chi-Square", mh)):
        p = math.erfc(math.sqrt(float(value) / 2))
        printed = [f"{float(value):.4f}", f"{p:.4f}"]
        assert label.split() + ["1"] + printed in rows
        stats[label] = {"formula_value": str(value), "df": 1, "probability": repr(p), "printed": printed}
    manifest["two_way"] = {"observed": observed, "expected": null_counts, "statistics": stats}
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("PASS: 110 complete tokens, status/severity, exact expected counts, independent probabilities and SVG positions")


if __name__ == "__main__":
    main()
