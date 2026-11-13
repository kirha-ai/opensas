#!/usr/bin/env python3
"""Run the frozen family. Default success means the discriminator completed.
--require-parity fails unless a model explains ALL known and fresh cases.
"""
import argparse
import csv
import hashlib
import itertools
import json
import re
import struct
import sys
from collections import defaultdict
from fractions import Fraction as F
from pathlib import Path

HERE = Path(__file__).resolve().parent
PARENT = HERE.parent
sys.path.insert(0, str(PARENT))
import halfgrid
from binary_model import Arithmetic, ORDERS, STORAGE, CONVERSIONS, rounded, self_test, ulp


def bits(value):
    return struct.pack('>d', float(value)).hex().upper()


def from_hex(value):
    return struct.unpack('>d', bytes.fromhex(value))[0]


def validate():
    for line in (HERE/'FROZEN-SHA256.txt').read_text().splitlines():
        digest, name = line.split('  ', 1)
        assert hashlib.sha256((HERE/name).read_bytes()).hexdigest() == digest, name
    self_test()
    raw = (PARENT/'dev2-sjpi-halfgrid-arithmetic.txt').read_text()
    entries = {}
    for chunk in re.split(r'\bid=', raw)[1:]:
        cid = int(chunk.split()[0])
        entries.setdefault(cid, {}).update(re.findall(r'(step|inv|centered|z|z2|bound|l|r|ld|rd)=([0-9A-F]{16})', chunk))
    meta = json.loads((PARENT/'dev2-sjpi-halfgrid-arithmetic-inputs.json').read_text())
    a = Arithmetic('binary64')
    count = 0
    for m in meta:
        lo, hi, x, k = map(F, (m['lo'], m['hi'], m['target'], m['k']))
        span = a.op('-', hi, lo)
        step = a.op('/', span, 200)
        inv = a.op('/', 1, step)
        centered = a.op('-', x, lo)
        left = a.op('+', lo, a.op('*', k, step))
        right = a.op('+', lo, a.op('*', k+1, step))
        values = dict(step=step, inv=inv, centered=centered,
                      z=a.op('/', centered, step), z2=a.op('*', centered, inv),
                      bound=a.op('+', lo, a.op('*', k+F(1, 2), step)),
                      l=left, r=right, ld=a.op('-', x, left), rd=a.op('-', right, x))
        for name, value in values.items():
            assert bits(value) == entries[m['global_id']][name], (m['global_id'], name)
            count += 1
    assert count == 1120
    return count


def known_cases():
    records = []
    for stem, cases, actual, stats, cs in halfgrid.batches():
        for row in cases:
            cid = row['id']
            x = actual[cid]
            assert x == row['values']
            n, q, sd = stats[cid]
            assert n == len(x)
            target_h = cs[cid]*q*n**(-.2)
            point = x.index(row['target'])
            hs = [halfgrid.forced(x, row['k'], point, b) for b in (0, 1)]
            matches = [b for b in (0, 1) if abs(hs[b]-target_h) < 1e-10]
            assert len(matches) == 1, (stem, cid, hs, target_h)
            records.append(dict(name=stem+':'+str(cid), group='known',
                                k=row['k'], low=min(x), high=max(x), x=row['target'],
                                observed_bin=row['k']+matches[0], oracle_h=target_h))
    assert len(records) == 136
    return records


def fresh_cases():
    path = HERE/'heldouts.txt'
    if not path.exists():
        return [], []
    raw = path.read_text()
    actual = defaultdict(list)
    for cid, point, value in re.findall(r'INPUT id=(\d+) point=(\d+) x=([0-9A-F]{16})', raw):
        actual[int(cid)].append(from_hex(value))
    result = {}
    for chunk in raw.split('RESULT ')[1:]:
        cid = int(re.search(r'id=(\d+)', chunk)[1])
        result[cid] = {key: from_hex(h) for key, h in re.findall(r'\b(q|sd|c|h)=([0-9A-F]{16})', chunk)}
    records, unresolved = [], []
    for row in json.loads((HERE/'heldouts-inputs.json').read_text()):
        cid = row['id']
        x = actual[cid]
        assert list(map(bits, x)) == list(map(bits, row['values'])), cid
        assert bits(row['target']) == row['target_hex']
        point = x.index(row['target'])
        hs = [halfgrid.forced(x, row['k'], point, b) for b in (0, 1)]
        target_h = result[cid]['h']
        matches = [b for b in (0, 1) if abs(hs[b]-target_h) < 1e-10]
        if len(matches) != 1:
            unresolved.append(dict(id=cid, candidate_h=hs, oracle_h=target_h, matches=matches))
            continue
        records.append(dict(name='heldouts:'+str(cid), group='fresh', k=row['k'],
                            low=min(x), high=max(x), x=row['target'],
                            observed_bin=row['k']+matches[0], oracle_h=target_h,
                            candidate_h=hs))
    return records, unresolved


def normalized(record):
    x, low, high = map(F, (record['x'], record['low'], record['high']))
    half = F(2*record['k']+1, 2)
    q = 200*(x-low)/(high-low)
    q53 = Arithmetic('binary64').coordinate(x, low, high, 'center_div')
    q64 = Arithmetic('extended64').coordinate(x, low, high, 'center_div')
    return dict(name=record['name'], group=record['group'], k=record['k'],
                low_hex=bits(low), high_hex=bits(high), x_hex=bits(x),
                observed_bin=record['observed_bin'], centered=str(x-low), span=str(high-low),
                q_exact=str(q), exact_offset_ulp53=str((q-half)/ulp(half, 53)),
                exact_offset_ulp64=str((q-half)/ulp(half, 64)),
                q_binary64=str(q53), q_extended64=str(q64),
                binary64_offset_ulp53=str((q53-half)/ulp(half, 53)),
                extended64_offset_ulp64=str((q64-half)/ulp(half, 64)))


def collisions(records):
    groups = defaultdict(list)
    for r in records:
        x, low, high = map(F, (r['x'], r['low'], r['high']))
        # Stronger than a rounded-q collision: EXACT centered operands agree.
        groups[(r['k'], x-low, high-low)].append(r)
    found = []
    for (k, a, span), group in sorted(groups.items()):
        left = next((r for r in group if r['observed_bin'] == k), None)
        right = next((r for r in group if r['observed_bin'] == k+1), None)
        if left and right:
            found.append(dict(k=k, centered=str(a), span=str(span), q_exact=str(200*a/span),
                              left=normalized(left), right=normalized(right)))
    return found


def evaluate(records):
    results = []
    for order, storage, conversion in itertools.product(ORDERS, STORAGE, CONVERSIONS):
        model = Arithmetic(storage)
        counts = dict(known=0, fresh=0)
        failures = []
        for r in records:
            q = model.coordinate(r['x'], r['low'], r['high'], order)
            selected = model.integer_bin(q, conversion)
            if selected == r['observed_bin']:
                counts[r['group']] += 1
            else:
                failures.append(dict(name=r['name'], group=r['group'], predicted_bin=selected,
                                     observed_bin=r['observed_bin'], q_evaluated=str(q),
                                     exact_offset_ulp53=normalized(r)['exact_offset_ulp53']))
        results.append(dict(order=order, storage=storage, conversion=conversion,
                            passed=counts, failures=failures))
    assert len(results) == 90
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--known-only', action='store_true')
    parser.add_argument('--require-parity', action='store_true')
    parser.add_argument('--out', type=Path, default=HERE)
    args = parser.parse_args()
    validation_count = validate()
    records = known_cases()
    fresh, unresolved = ([], []) if args.known_only else fresh_cases()
    records += fresh
    rows = [dict(case_index=i, **normalized(r)) for i, r in enumerate(records)]
    result = evaluate(records)
    witnesses = collisions(records)
    args.out.mkdir(parents=True, exist_ok=True)
    prefix = 'known' if args.known_only else 'combined'
    with (args.out/(prefix+'-normalized.csv')).open('w', newline='') as output:
        writer = csv.DictWriter(output, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    accepted = [r for r in result if not r['failures'] and len(fresh) == 27 and not unresolved]
    saved_models = []
    case_indices = {r['name']: i for i, r in enumerate(records)}
    for r in result:
        saved = {key: r[key] for key in ('order', 'storage', 'conversion', 'passed')}
        saved['failed_case_indices'] = [case_indices[f['name']] for f in r['failures']]
        saved['counterexamples'] = {g: next((f for f in r['failures'] if f['group'] == g), None) for g in ('known', 'fresh')}
        saved_models.append(saved)
    fresh_error = max((abs(r['candidate_h'][r['observed_bin']-r['k']]-r['oracle_h']) for r in fresh), default=0)
    report = dict(validated_binary64_intermediates=validation_count, known_count=136,
                  fresh_resolved=len(fresh), fresh_unresolved=unresolved,
                  fresh_assignments=fresh, fresh_max_bandwidth_error=fresh_error,
                  case_order=[r['name'] for r in records],
                  centered_operand_collisions=witnesses, models=saved_models, accepted=accepted)
    encoded = json.dumps(report, indent=2)
    # Keep generated failure-index arrays compact while retaining readable
    # model definitions, exact witnesses and the complete index-to-name map.
    encoded = re.sub(r'"failed_case_indices": \[\s*([0-9,\s]*)\]',
                     lambda m: '"failed_case_indices": '+json.dumps([int(v) for v in m[1].split(',') if v.strip()]), encoded)
    (args.out/(prefix+'-results.json')).write_text(encoded+'\n')
    print(f'Validation: {validation_count}/1120 SAS binary64 intermediates; exact rounding self-tests passed.')
    print(f'Oracle assignments: 136 known, {len(fresh)} fresh resolved, {len(unresolved)} fresh unresolved.')
    if fresh:
        print(f'Fresh forced-bin bandwidth comparison: max absolute error {fresh_error:.6g}, tolerance 1e-10.')
    print('Frozen candidates: 90; no fitted tolerances, per-index table or post-freeze additions.')
    print('order / storage / conversion: known, fresh')
    for r in sorted(result, key=lambda r:(-r['passed']['known'], -r['passed']['fresh'], r['order'], r['storage'], r['conversion']))[:12]:
        print(f'{r["order"]} / {r["storage"]} / {r["conversion"]}: {r["passed"]["known"]}/136, {r["passed"]["fresh"]}/{len(fresh)}')
    print(f'Exact centered-operand collision groups: {len(witnesses)}')
    for witness in witnesses[:3]:
        print(f'COLLISION k={witness["k"]}, x-low={witness["centered"]}, span={witness["span"]}, q={witness["q_exact"]}')
        for side in ('left', 'right'):
            row = witness[side]
            print(f'  {side}: {row["name"]}; low={row["low_hex"]} high={row["high_hex"]} x={row["x_hex"]}; bin={row["observed_bin"]}')
    print(f'Candidates passing all known: {sum(r["passed"]["known"]==136 for r in result)}/90; accepted after fresh validation: {len(accepted)}/90.')
    if not accepted:
        print('Raw selector NOT ACCEPTED. This rejects the frozen family, not all possible internal C/x87 arithmetic.')
    return int(args.require_parity and not accepted)


if __name__ == '__main__':
    sys.exit(main())
