#!/usr/bin/env python3
"""Full COMMON004 oracle verification; no reference-output rewriting.

The REG listing and all nonnumeric OUTEST fields/panel headers are exact after
whitespace tokenization. BEST32 values from BOTH outputs are independently checked
against Fraction normal equations with Decimal(80) square roots. See evidence.md
for the componentwise gamma-operation error budgets (never fitted to differences).
"""
from decimal import Decimal, localcontext
from fractions import Fraction as F
from pathlib import Path
import argparse
import difflib
import hashlib
import json
import subprocess


def decimal(v):
    return Decimal(v.numerator) / Decimal(v.denominator) if isinstance(v, F) else Decimal(v)


def gamma(k):
    u = F(1, 2**53)  # unit roundoff = machine epsilon / 2
    return k * u / (1 - k * u)


def inverse(a):
    n = len(a)
    work = [list(row) + [F(int(i == j)) for j in range(n)] for i, row in enumerate(a)]
    for j in range(n):
        pivot = next(i for i in range(j, n) if work[i][j])
        work[j], work[pivot] = work[pivot], work[j]
        divisor = work[j][j]
        work[j] = [v / divisor for v in work[j]]
        for i in range(n):
            if i != j:
                factor = work[i][j]
                work[i] = [u - factor * v for u, v in zip(work[i], work[j])]
    return [row[n:] for row in work]


def reference(source):
    # This verifier is intentionally for the named oracle, not a SAS parser.
    block = source.split('datalines;', 1)[1].split(';', 1)[0]
    records = [line.split() for line in block.splitlines() if line.strip()]
    x = [[F(1), F(row[0]), F(row[1])] for row in records]
    y = [F(row[2]) for row in records]
    w = [F(row[4]) for row in records]
    n, p = len(x), len(x[0])
    a = [[sum(wi * r[j] * r[k] for r, wi in zip(x, w)) for k in range(p)] for j in range(p)]
    g = inverse(a)
    b = [sum(wi * r[j] * yi for r, yi, wi in zip(x, y, w)) for j in range(p)]
    beta = [sum(g[j][k] * b[k] for k in range(p)) for j in range(p)]
    assert all(sum(a[i][k]*g[k][j] for k in range(p)) == int(i == j) for i in range(p) for j in range(p))
    assert all(sum(a[i][k]*beta[k] for k in range(p)) == b[i] for i in range(p))
    residual = [yi - sum(xi[j] * beta[j] for j in range(p)) for xi, yi in zip(x, y)]
    sse = sum(wi * ri**2 for wi, ri in zip(w, residual))
    mse = sse / (n - p)
    cov = [[mse * q for q in row] for row in g]

    # Source-derived operation envelopes: compensated dot has at most six
    # rounded arithmetic operations per term; two more cover conversion/subtract.
    # These are identity-residual acceptance budgets, not a promise that every
    # possible QR input attains them. Exact reference quantities fix all scales.
    row_eval = [gamma(6*p + 2) * (abs(yi) + sum(abs(xi[j]*beta[j]) for j in range(p)))
                for xi, yi in zip(x, y)]
    normal_budget = []
    for j in range(p):
        evaluation = sum(abs(wi*xi[j])*err for wi, xi, err in zip(w, x, row_eval))
        magnitude = sum(abs(wi*xi[j]*ri) for wi, xi, ri in zip(w, x, residual))
        normal_budget.append(evaluation + gamma(7*n + 2)*(magnitude + evaluation))
    # beta error = A^-1 * normal-equation residual: componentwise conditioning.
    beta_budget = [sum(abs(g[j][k])*normal_budget[k] for k in range(p)) for j in range(p)]
    prediction_budget = [sum(abs(xi[j])*beta_budget[j] for j in range(p)) for xi in x]
    # X'Wr=0 cancels the first-order coefficient error in residual SS.
    quadratic = sum(beta_budget[j]*abs(a[j][k])*beta_budget[k] for j in range(p) for k in range(p))
    evaluation_ss = sum(wi*(2*(abs(ri)+pb)*er + er*er)
                        for wi, ri, pb, er in zip(w, residual, prediction_budget, row_eval))
    sse_budget = quadratic + evaluation_ss + gamma(8*n + 2)*(sse + quadratic + evaluation_ss)
    mse_budget = sse_budget/(n-p) + gamma(1)*mse
    # AC = mse I. A small matrix product/subtraction has at most 6p+2
    # operations per entry; premultiply its residual budget by |A^-1|.
    covariance_budget = [[F(0) for _ in range(p)] for _ in range(p)]
    covariance_residual_budget = [[F(0) for _ in range(p)] for _ in range(p)]
    for j in range(p):
        residual_budget = [gamma(6*p + 2)*(sum(abs(a[k][l]*cov[l][j]) for l in range(p))
                                          + (mse if k == j else 0))
                           for k in range(p)]
        for i in range(p):
            covariance_residual_budget[i][j] = residual_budget[i]
            covariance_budget[i][j] = (sum(abs(g[i][k])*residual_budget[k] for k in range(p))
                                       + abs(g[i][j])*mse_budget + gamma(1)*abs(cov[i][j]))
    rmse = decimal(mse).sqrt()
    rmse_budget = decimal(mse_budget)/(rmse + decimal(mse-mse_budget).sqrt()) + decimal(gamma(1))*rmse
    norm_a = max(sum(abs(v) for v in row) for row in a)
    norm_g = max(sum(abs(v) for v in row) for row in g)
    return dict(n=n, p=p, A=a, G=g, b=b, beta=beta, residual=residual, weights=w, X=x,
                mse=mse, cov=cov, rmse=rmse, beta_budget=beta_budget,
                cov_budget=covariance_budget, rmse_budget=rmse_budget,
                mse_budget=mse_budget, normal_budget=normal_budget,
                condition_inf=norm_a*norm_g, cov_residual_budget=covariance_residual_budget)


def parse_listing(text):
    lines = text.splitlines()
    start = next(i for i, line in enumerate(lines) if line.split()[:1] == ['_MODEL_'])
    prefix = '\n'.join(lines[:start]).split()
    content = [line.split() for line in lines[start:] if line.strip()]
    headers = [['_MODEL_', '_TYPE_', '_NAME_', '_DEPVAR_', '_RMSE_', 'Intercept'], ['x', 'z', 'y']]
    assert len(content) == 10, ('Unexpected panel/row count', len(content))
    assert content[0] == headers[0] and content[5] == headers[1], ('Panel columns differ', content[0], content[5])
    rows = []
    for i in range(4):
        first = content[1+i][:]
        if i == 0:
            assert len(first) == 5 and first[1] == 'PARMS', first
            first.insert(2, '')  # the documented blank PARMS _NAME_ cell
        assert len(first) == 6 and len(content[6+i]) == 3
        rows.append(dict(zip(headers[0]+headers[1], first+content[6+i])))
    return prefix, headers, rows


def rounding(token):
    # Quantization is determined by the printed decimal's last place, not error.
    return Decimal(5).scaleb(Decimal(token).as_tuple().exponent - 1)


def validate_rows(rows, refs, label, declared_precision):
    checks = []
    parameters = ['Intercept', 'x', 'z']
    for i, row in enumerate(rows):
        assert row['_MODEL_'] == 'MODEL1'
        assert row['_TYPE_'] == ('PARMS' if i == 0 else 'COV')
        assert row['_NAME_'] == ('' if i == 0 else parameters[i-1])
        assert row['_DEPVAR_'] == 'y'
        assert row['y'] == ('-1' if i == 0 else '.')
        for name in ['_RMSE_'] + parameters:
            if name == '_RMSE_':
                target, bound = refs['rmse'], refs['rmse_budget']
                family = 'root_mse'
            else:
                j = parameters.index(name)
                target = decimal(refs['beta'][j] if i == 0 else refs['cov'][i-1][j])
                bound = decimal(refs['beta_budget'][j] if i == 0 else refs['cov_budget'][i-1][j])
                family = 'coefficient' if i == 0 else 'covariance'
            value = Decimal(row[name])
            assert value.is_finite()
            quantization = rounding(declared_precision[i][name])
            # The immutable oracle sets the display resolution for BOTH sides.
            # A producer cannot enlarge its allowance by printing fewer digits.
            if value != target:
                assert rounding(row[name]) <= quantization, (label, i, name, 'insufficient displayed precision')
            error = abs(value-target)
            assert error <= bound + quantization, (label, i, name, value, target, error, bound)
            checks.append(dict(output=label, row=i+1, column=name, family=family,
                               text=row[name], reference=str(target), absolute_error=str(error),
                               arithmetic_bound=str(bound), decimal_quantization_bound=str(quantization)))
    # Residual certificates independently test the defining matrix equations
    # in exact arithmetic for the printed candidate values, including all
    # off-diagonal covariance entries. Display uncertainty uses oracle precision.
    beta_values = [F(rows[0][name]) for name in parameters]
    beta_quantum = [F(rounding(declared_precision[0][name])) for name in parameters]
    for i in range(refs['p']):
        error = abs(sum(refs['A'][i][j]*beta_values[j] for j in range(refs['p'])) - refs['b'][i])
        bound = refs['normal_budget'][i] + sum(abs(refs['A'][i][j])*beta_quantum[j] for j in range(refs['p']))
        assert error <= bound, (label, 'normal equations', i, error, bound)
    for i in range(refs['p']):
        for j, name in enumerate(parameters):
            error = abs(sum(refs['A'][i][k]*F(rows[k+1][name]) for k in range(refs['p']))
                        - (refs['mse'] if i == j else 0))
            bound = (refs['cov_residual_budget'][i][j] + (refs['mse_budget'] if i == j else 0)
                     + sum(abs(refs['A'][i][k])*F(rounding(declared_precision[k+1][name])) for k in range(refs['p'])))
            assert error <= bound, (label, 'covariance identity', i, j, error, bound)
    return checks


def compare(expected, actual, source):
    with localcontext() as ctx:
        ctx.prec = 80
        refs = reference(source)
        ep, eh, er = parse_listing(expected)
        ap, ah, ar = parse_listing(actual)
        assert ep == ap, 'REG listing differs (no numeric tolerance applies before OUTEST)'
        assert eh == ah
        for e, a in zip(er, ar):
            for col in ['_MODEL_', '_TYPE_', '_NAME_', '_DEPVAR_', 'y']:
                assert e[col] == a[col], (col, e[col], a[col])
        checks = validate_rows(er, refs, 'SAS oracle', er) + validate_rows(ar, refs, 'OpenSAS', er)
        differences = [dict(row=i+1, column=c, expected=e[c], actual=a[c],
                            absolute_difference=str(abs(Decimal(e[c])-Decimal(a[c]))))
                       for i, (e, a) in enumerate(zip(er, ar))
                       for c in ['_RMSE_', 'Intercept', 'x', 'z'] if e[c] != a[c]]
        return dict(status='pass', normalization='whitespace only outside named BEST32 numeric cells',
                    numeric_rule='both outputs against independent rational reference and source-derived gamma bounds',
                    rows=4, columns=9, panels=2, REG_tokens=len(ep), unit_roundoff='2^-53',
                    condition_inf=str(refs['condition_inf']), normal_matrix=[[str(v) for v in row] for row in refs['A']],
                    beta_rational=[str(v) for v in refs['beta']], mse_rational=str(refs['mse']),
                    covariance_rational=[[str(v) for v in row] for row in refs['cov']],
                    checks=checks, raw_numeric_differences=differences,
                    max_raw_numeric_difference=str(max((Decimal(d['absolute_difference']) for d in differences), default=Decimal(0))))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--binary', default='zig-out/bin/opensas')
    parser.add_argument('--output-dir', default='.zig-cache/stat-common-004-evidence')
    args = parser.parse_args()
    fixture = Path(__file__).resolve().parent
    out = Path(args.output_dir); out.mkdir(parents=True, exist_ok=True)
    source = (fixture/'weighted_linear_moments.sas').read_text()
    expected_bytes = (fixture/'weighted_linear_moments.expected.txt').read_bytes()
    result = subprocess.run([args.binary, str(fixture/'weighted_linear_moments.sas')], capture_output=True, text=True)
    (out/'actual.txt').write_text(result.stdout)
    (out/'actual.log').write_text(result.stderr)
    expected = expected_bytes.decode()
    (out/'raw-token.diff').write_text('\n'.join(difflib.unified_diff(expected.split(), result.stdout.split(), fromfile='SAS expected', tofile='OpenSAS actual', lineterm=''))+'\n')
    assert result.returncode == 0, (result.returncode, result.stderr)
    assert result.stderr == '', result.stderr
    report = compare(expected, result.stdout, source)
    report.update(expected_status=0, actual_status=result.returncode, stderr=result.stderr,
                  expected_sha256=hashlib.sha256(expected_bytes).hexdigest(),
                  sha=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
                  version=subprocess.check_output([args.binary, '--version'], text=True).strip())
    # Discriminating checks on the verifier: wrong identity/missingness and a
    # changed covariance must fail; no rows or notes are discarded to pass.
    mutants = [result.stdout.replace('MODEL1', 'MODEL2', 1),
               result.stdout.replace('COV', 'WRONG', 1),
               result.stdout.replace('0.511685', '0.512685', 1),
               result.stdout.replace(parse_listing(result.stdout)[2][1]['Intercept'], '1', 1),
               result.stdout.replace('COV', '', 1)]
    for mutant in mutants:
        assert mutant != result.stdout
        try:
            compare(expected, mutant, source)
        except (AssertionError, ValueError):
            pass
        else:
            raise AssertionError('Verifier accepted a changed identity/covariance')
    report['verifier_mutations_rejected'] = len(mutants)
    (out/'verification.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({k: report[k] for k in ['status','sha','version','expected_status','actual_status','rows','columns','panels','REG_tokens','max_raw_numeric_difference','verifier_mutations_rejected']}, indent=2))

if __name__ == '__main__':
    main()
