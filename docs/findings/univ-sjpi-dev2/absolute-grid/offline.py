#!/usr/bin/env python3
"""Evaluate the frozen absolute-grid family on all 163 retained assignments."""
from pathlib import Path
import argparse
import csv
import hashlib
import importlib.util
import itertools
import json
import re
import sys

HERE = Path(__file__).resolve().parent
PARENT = HERE.parent
sys.path.insert(0, str(PARENT/'extended-precision'))
spec = importlib.util.spec_from_file_location('sjpi_previous_report', PARENT/'extended-precision'/'analyze.py')
prior = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prior)
from grids import GENERATORS, DECISIONS, centers, select, bits, self_test


def check_frozen():
    for line in (HERE/'FROZEN-SHA256.txt').read_text().splitlines():
        digest, name = line.split('  ', 1)
        assert hashlib.sha256((HERE/name).read_bytes()).hexdigest() == digest, name
    self_test()


def load_old():
    records = prior.known_cases()
    fresh, unresolved = prior.fresh_cases()
    assert len(records) == 136 and len(fresh) == 27 and not unresolved
    return records+fresh


def compact_json(value):
    encoded = json.dumps(value, indent=2)
    return re.sub(r'"failed_case_indices": \[\s*([0-9,\s]*)\]',
                  lambda m: '"failed_case_indices": '+json.dumps([int(v) for v in m[1].split(',') if v.strip()]), encoded)+'\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--require-parity', action='store_true')
    args = parser.parse_args()
    check_frozen()
    records = load_old()
    rows = []
    for i, r in enumerate(records):
        rows.append(dict(case_index=i, name=r['name'], k=r['k'], low_hex=bits(r['low']),
                         high_hex=bits(r['high']), x_hex=bits(r['x']), observed_bin=r['observed_bin']))
    results = []
    for generator, decision in itertools.product(GENERATORS, DECISIONS):
        failures = []
        first = None
        for i, r in enumerate(records):
            predicted = select(r['low'], r['high'], r['k'], r['x'], generator, decision)
            if predicted != r['observed_bin']:
                failures.append(i)
                if first is None:
                    a, b = centers(r['low'], r['high'], generator)[r['k']:r['k']+2]
                    first = dict(**rows[i], predicted_bin=predicted, center_k_hex=bits(a),
                                 center_next_hex=bits(b), sum_mid_hex=bits((a+b)/2),
                                 gap_mid_hex=bits(a+(b-a)/2), left_distance_hex=bits(abs(r['x']-a)),
                                 right_distance_hex=bits(abs(b-r['x'])))
        results.append(dict(generator=generator, decision=decision, passed=len(records)-len(failures),
                            failed_case_indices=failures, first_counterexample=first,
                            prior_family_recheck=generator in GENERATORS[:6]))
    viable = [r for r in results if not r['failed_case_indices']]
    report = dict(old_count=len(records), model_count=len(results), case_order=[r['name'] for r in records],
                  models=results, viable=viable)
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out/'offline-results.json').write_text(compact_json(report))
    with (args.out/'old-cases.csv').open('w', newline='') as output:
        writer = csv.DictWriter(output, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print('Retained assignments: 163/163; frozen absolute-grid configurations: 72.')
    for generator in GENERATORS:
        family = [r for r in results if r['generator'] == generator]
        best = max(family, key=lambda r:r['passed'])
        print(f'{generator}: {best["passed"]}/163 ({best["decision"]}); first failure {best["first_counterexample"]["name"] if best["first_counterexample"] else "none"}')
    print(f'Viable configurations: {len(viable)}/72.')
    print('Next branch: '+('prespecified fresh validation' if viable else 'six prespecified bounded ULP threshold searches'))
    return int(args.require_parity and not viable)


if __name__ == '__main__':
    sys.exit(main())
