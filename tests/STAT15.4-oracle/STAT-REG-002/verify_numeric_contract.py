#!/usr/bin/env python3
"""REG-002 oracle: exact tokens except two analytically-zero residual sums.

No external packages. See numeric-contract.md for the derivation and limitations.
The bounds depend on source data and exact coefficients, never on observed tails.
"""
import argparse
from fractions import Fraction as F
import hashlib
import json
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
U = F(1, 2**53)


def gamma(k):
    return k * U / (1 - k * U)


def exact_fit(x, y):
    """Independent, test-only rational normal equations; p is two or three."""
    p = len(x[0])
    rows = [[sum(row[j] * row[k] for row in x) for k in range(p)] +
            [sum(row[j] * value for row, value in zip(x, y))] for j in range(p)]
    for j in range(p):
        pivot = next(i for i in range(j, p) if rows[i][j])
        rows[j], rows[pivot] = rows[pivot], rows[j]
        scale = rows[j][j]
        rows[j] = [v / scale for v in rows[j]]
        for i in range(p):
            if i != j:
                scale = rows[i][j]
                rows[i] = [a - scale * b for a, b in zip(rows[i], rows[j])]
    beta = [row[-1] for row in rows]
    residuals = [value - sum(a * b for a, b in zip(row, beta)) for row, value in zip(x, y)]
    assert all(sum(row[j] * r for row, r in zip(x, residuals)) == 0 for j in range(p))
    return beta, residuals


def reference_contract(source):
    block = re.search(r'data\s+USPopulation\s*;(.*?)datalines\s*;(.*?)\n\s*;', source, re.I | re.S)
    if not block:
        raise ValueError('Expected the documented USPopulation input block')
    setup, values = block.groups()
    first = F(re.search(r'retain\s+Year\s+([0-9]+)\s*;', setup, re.I)[1])
    step = F(re.search(r'Year\s*=\s*Year\s*\+\s*([0-9]+)', setup, re.I)[1])
    divisor = F(re.search(r'Population\s*=\s*Population\s*/\s*([0-9]+)', setup, re.I)[1])
    assert re.search(r'YearSq\s*=\s*Year\s*\*\s*Year\s*;', setup, re.I)
    if re.search(r'^\s*(?:weight|freq|restrict)\s+', source, re.I | re.M) or re.search(r'\bnoint\b', source, re.I):
        raise ValueError('This contract is limited to unrestricted, unweighted intercept models')
    y = [F(v) / divisor for v in values.split()]
    years = [first + (i + 1) * step for i in range(len(y))]
    result = []
    for p in (2, 3):
        x = [[F(1), year, year * year][:p] for year in years]
        beta, residuals = exact_fit(x, y)
        assert sum(residuals) == 0  # intercept identity, exact rational zero
        envelope = sum(abs(value) + sum(abs(a * b) for a, b in zip(row, beta))
                       for row, value in zip(x, y))
        residual_l1 = sum(abs(v) for v in residuals)
        evaluation = gamma(2 * p + 2) * envelope
        bound = evaluation + gamma(len(y) - 1) * (residual_l1 + evaluation)
        result.append({'model': 'linear' if p == 2 else 'quadratic', 'n': len(y), 'p': p,
                       'coefficients': [str(v) for v in beta], 'exact_residual_sum': '0',
                       'envelope': float(envelope), 'residual_l1': float(residual_l1),
                       'cancellation_amplification': float(envelope / sum(abs(v) for v in y)),
                       'bound_fraction': str(bound), 'bound': float(bound)})
    return result


def residual_slots(text):
    """Locate only complete named scalar lines inside Population output sections."""
    model = dependent = None
    slots = []
    token_offset = 0
    output_statistics = False
    for line in text.splitlines():
        if line.startswith('Model:'):
            model = line.split(':', 1)[1].strip()
            output_statistics = False
        if line.startswith('Dependent Variable:'):
            dependent = line.split(':', 1)[1].strip()
        if line.strip() == 'Output Statistics':
            output_statistics = True
        match = re.fullmatch(r'\s*Sum of Residuals\s+(\S+)\s*', line)
        if match:
            if dependent != 'Population' or not output_statistics:
                raise ValueError('Residual sum is not in the expected Population output section')
            slots.append((token_offset + 3, model, match[1]))
        token_offset += len(line.split())
    if [s[1] for s in slots] != ['MODEL1', 'MODEL1.1']:
        raise ValueError('Missing, extra, reordered, or renamed residual-sum fields')
    return slots


def compare(expected, actual, contracts):
    want, got = expected.split(), actual.split()
    es, ats = residual_slots(expected), residual_slots(actual)
    records = []
    failures = []
    if len(want) != len(got):
        failures.append('token_count')
    for (ei, em, e), (ai, am, a), contract in zip(es, ats, contracts):
        if (ei, em) != (ai, am):
            failures.append('field_position')
        bound = F(contract['bound_fraction'])
        try:
            expected_ok, actual_ok = abs(F(e)) <= bound, abs(F(a)) <= bound
        except (ValueError, ZeroDivisionError):
            expected_ok = actual_ok = False
        if not expected_ok or not actual_ok:
            failures.append('residual_sum_bound')
        records.append({'model': contract['model'], 'expected': e, 'actual': a,
                        'expected_within_bound': expected_ok, 'actual_within_bound': actual_ok,
                        'absolute_bound': contract['bound'], 'tolerant_acceptance_used': e != a})
        # Values are retained above and checked independently against analytic zero.
        # Replace only these two verified slots; all other token comparisons are exact.
        want[ei] = got[ai] = '<analytically-zero-residual-sum>'
    if want != got:
        failures.append('other_tokens')
    return {'accepted': not failures, 'failures': failures,
            'strict_whitespace_match': expected.split() == actual.split(),
            'all_other_tokens_exact': want == got, 'fields': records,
            'expected_tokens': len(want), 'actual_tokens': len(got)}


def mutation_checks(expected, actual, contracts):
    def rejected(candidate):
        try:
            return not compare(expected, candidate, contracts)['accepted']
        except (ValueError, IndexError):
            return True
    slots = residual_slots(actual)
    first = slots[0][2]
    bad_sum = str(float(F(contracts[0]['bound_fraction']) * 4))
    candidates = {
        'out_of_bound_residual_sum': actual.replace('Sum of Residuals ' + first, 'Sum of Residuals ' + bad_sum, 1),
        'missing_residual_sum': re.sub(r'^Sum of Residuals[^\n]*\n', '', actual, count=1, flags=re.M),
        'extra_residual_sum': actual + '\nSum of Residuals 0\n',
        'renamed_parameter': actual.replace('Intercept', 'Intercept_changed', 1),
        'changed_anova_number': actual.replace('7193.24912', '7193.24913', 1),
        'missing_table_heading': actual.replace('Analysis of Variance', '', 1),
        'missing_marker_in_sum': actual.replace('Sum of Residuals ' + first, 'Sum of Residuals .', 1),
    }
    checks = {name: candidate != actual and rejected(candidate) for name, candidate in candidates.items()}
    assert all(checks.values()), checks
    return checks


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--binary', type=Path, default=ROOT / 'zig-out/bin/opensas')
    ap.add_argument('--report', type=Path)
    args = ap.parse_args()
    program = HERE / 'documented_default.sas'
    source = program.read_text()
    expected = (HERE / 'documented_default.expected.txt').read_text()
    contracts = reference_contract(source)
    run = subprocess.run([str(args.binary.resolve()), str(program)], cwd=ROOT, capture_output=True, text=True)
    result = compare(expected, run.stdout, contracts)
    expected_diagnostics = (HERE / 'documented_default.expected.diagnostics.txt').read_text().splitlines()
    warning_error = [line for line in run.stderr.splitlines() if line.startswith(('WARNING', 'ERROR'))]
    notes = [re.sub(r'^NOTE(?:\([^)]*\))?: ', '', line) for line in run.stderr.splitlines() if line.startswith('NOTE')]
    oracle_log = (HERE / 'documented_default.oracle.log').read_text()
    known_notes = all('NOTE: ' + note in oracle_log for note in notes)
    diagnostics_ok = warning_error == [v for v in expected_diagnostics if v] and known_notes
    expected_rc = int((HERE / 'documented_default.expected.rc').read_text())
    checks = mutation_checks(expected, run.stdout, contracts)
    result.update({'ticket': 'STAT-REG-002', 'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                   'binary_version': subprocess.check_output([str(args.binary.resolve()), '--version'], text=True).strip(),
                   'actual_rc': run.returncode, 'expected_rc': expected_rc, 'diagnostics_match': diagnostics_ok,
                   'stderr': run.stderr, 'reference': contracts, 'negative_controls': checks,
                   'expected_sha256': hashlib.sha256(expected.encode()).hexdigest(),
                   'program_sha256': hashlib.sha256(source.encode()).hexdigest()})
    result['accepted'] = result['accepted'] and run.returncode == expected_rc and diagnostics_ok
    report = json.dumps(result, indent=2) + '\n'
    if args.report:
        args.report.write_text(report)
    print(report)
    return 0 if result['accepted'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
