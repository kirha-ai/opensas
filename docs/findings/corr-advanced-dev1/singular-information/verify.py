"""Check the retained SAS discriminators; no numerical threshold is fitted."""
from pathlib import Path
import math
ROOT = Path(__file__).resolve().parent

def tagged(name, prefixes, tag_words):
    rows = {}
    for line in (ROOT / name).read_text().splitlines():
        if not line.strip().startswith(prefixes):
            continue
        parts = line.split()
        rows[' '.join(parts[:tag_words])] = tuple(None if v == '.' else float(v) for v in parts[tag_words:])
    return rows

mapping = tagged('singular-map.txt', ('SING=', 'DS='), 2)
for singular in ('0', '1e-16', '1e-12', '1e-8', '.01', '.5'):
    for convergence in ('.0001', '.00001'):
        assert mapping[f'SING={singular} C={convergence}'] == mapping[f'SING=0 C={convergence}']
steps = tagged('singular-step.txt', ('d M=', 'tr M=', 'scaled M=', 'held M=', 'held C='), 2)
for case in ('d', 'tr', 'scaled'):
    for limit in (21, 22):
        assert steps[f'{case} M={limit}'] == (None,) * 4
    for limit in (23, 24, 25):
        rho, se, wald, lr = steps[f'{case} M={limit}']
        assert rho > .9998 and se == 0 and wald is None and lr > 0
for limit in (21, 22, 23):
    assert steps[f'held M={limit}'] == (None,) * 4
for tag in ('held M=24', 'held M=25', 'held C=1e-6', 'held C=1e-8', 'held C=1e-12'):
    rho, se, wald, lr = steps[tag]
    assert rho == .9999 and se == 0 and wald is None and lr > 0
assert math.isclose(steps['scaled M=23'][3], 100 * steps['d M=23'][3], abs_tol=1e-9)
transition = tagged('singular-transition.txt', ('C=',), 1)
assert transition['C=.000029'][1] > 4
assert transition['C=.000026'][1] == 0

rank = {}
for line in (ROOT / 'ginverse-rank.txt').read_text().splitlines():
    try:
        row = [float(x) for x in line.split()]
    except ValueError:
        continue
    if len(row) == 5:
        rank[tuple(map(int, row[:3]))] = tuple(row[3:])
assert len(rank) == 66
for dim in (2, 5, 10):
    for exponent in range(-8, -19, -1):
        a, b = rank[dim, 1, exponent][0], rank[dim, 100, exponent][0]
        assert (a == 0) == (b == 0)
        if a:
            assert math.isclose(a, 100*b, rel_tol=1e-12)
assert rank[5, 1, -13][0] > 0 and rank[10, 1, -13][0] == 0
assert rank[2, 1, -13][1] == 0 and rank[2, 100, -13][1] > 0

def traces(name):
    result = {1: [], 2: []}
    current = None
    for line in (ROOT / name).read_text().splitlines():
        try:
            row = [float(x) for x in line.split()]
        except ValueError:
            continue
        if len(row) == 8:
            current = int(row.pop(0))
        if len(row) == 7 and current in result:
            result[current].append(row)
    return result
for name, expected_steps in [('iml-scoring.txt', (30, 30)), ('iml-sweep-scoring.txt', (30, 31))]:
    result = traces(name)
    for case, expected_step, proc_case in zip((1, 2), expected_steps, ('d', 'held')):
        last = result[case][-1]
        assert last[0] == expected_step and last[-1] == 4
        assert last[-2] < 1e-20
        assert abs(last[2] - steps[f'{proc_case} M=25'][0]) > 1e-4
        if name == 'iml-scoring.txt':
            assert 0 < last[3] < 1e-9
        else:
            assert last[3] == 0
print('PASS: SINGULAR invariance; stopping steps; scale/dimension inverse behavior; GINV/SWEEP trajectory counterexamples')
