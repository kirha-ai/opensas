#!/usr/bin/env python3
"""Execute/report ONLY the preregistered six bounded transition searches.

No network calls: generate SAS source, invoke sasrun separately, then observe.
Measured thresholds are evidence only, never inputs to a runtime selector.
"""
from pathlib import Path
from fractions import Fraction as F
import argparse
import csv
import hashlib
import itertools
import json
import math
import re
import struct

from grids import GENERATORS, DECISIONS, centers, select, bits, rank, unrank
from offline import HERE, check_frozen, prior


def read(path):
    return json.loads(path.read_text())


def save(path, value):
    path.write_text(json.dumps(value, indent=2)+'\n')


def stop(work, state, reason):
    state['status'] = 'unresolved'
    state['reason'] = reason
    save(work/'state.json', state)
    raise RuntimeError(reason)


def make_query(target, key, qid):
    low, high = target['low'], target['high']
    x = unrank(key)
    values = sorted([float(F(low)+(F(high)-F(low))*F(i, 200)) for i in target['background_indices']]+[x])
    return dict(qid=qid, target_id=target['id'], k=target['k'], low=low, high=high,
                rank=str(key), offset=key-int(target['midpoint_rank']), x_hex=bits(x), values=values)


def generate(work, round_number):
    assert 0 <= round_number <= 7
    assert not read(work/'offline-results.json')['viable'], 'Use the frozen viable-model heldout branch instead.'
    state_path = work/'state.json'
    if state_path.exists():
        state = read(state_path)
    else:
        assert round_number == 0
        state = dict(status='active', next_round=0, targets=read(HERE/'targets.json'), observations=[])
    assert state['status'] == 'active' and state['next_round'] == round_number
    if (work/f'round-{round_number}.json').exists():
        print(f'Round {round_number} already generated; source is unchanged.')
        return
    queries = []
    for target in state['targets']:
        middle = int(target['midpoint_rank'])
        if round_number == 0:
            keys = [middle-32, middle+32]
        elif round_number == 7:
            left, right = int(target['last_left']), int(target['first_right'])
            assert right-left == 1
            keys = [left-1, left, right, right+1]
        else:
            left, right = int(target['last_left']), int(target['first_right'])
            assert right-left > 1
            keys = [(left+right)//2]
        for key in keys:
            queries.append(make_query(target, key, len(queries)))
    assert len(state['observations'])+len(queries) <= 72
    lines = []
    for query in queries:
        for point, value in enumerate(query['values']):
            lines.append(f'{query["qid"]} {point} {bits(value)}')
    source = '''ods graphics off;
data _null_;file print;put "SAS_VERSION=&sysvlong4";run;
data all;input qid point x :hex16.;datalines;
'''+ '\n'.join(lines)+'''
;
data _null_;set all;file print;put 'INPUT ' qid= point= x=hex16.;run;
proc univariate data=all noprint;by qid;var x;
output out=stats n=n qrange=q std=sd;
histogram x / noplot kernel(c=sjpi) outkernel=kernel;run;
data one;set kernel;by qid;if first.qid;keep qid _c_;run;
data _null_;merge one stats;by qid;file print;
c=_c_;h=c*q*n**(-.2);
put 'RESULT ' qid= n= q=hex16. sd=hex16. c=hex16. h=hex16.;run;
'''
    save(work/f'round-{round_number}.json', dict(round=round_number, queries=queries,
         source_sha256=hashlib.sha256(source.encode()).hexdigest()))
    (work/f'round-{round_number}.sas').write_text(source)
    oracle_path = Path(f'/private/tmp/dev2-sjpi-absgrid-r{round_number}.sas')
    oracle_path.write_text(source)
    state['last_generated'] = round_number
    save(state_path, state)
    print(f'Round {round_number}: {len(queries)} queries; {oracle_path}')


def observe(work, round_number):
    state = read(work/'state.json')
    assert state['status'] == 'active' and state['next_round'] == round_number
    manifest = read(work/f'round-{round_number}.json')
    assert hashlib.sha256((work/f'round-{round_number}.sas').read_bytes()).hexdigest() == manifest['source_sha256']
    raw = (work/f'round-{round_number}.txt').read_text()
    assert 'SAS_VERSION=9.04.01M9' in raw
    actual = {}
    for qid, point, value in re.findall(r'INPUT qid=(\d+) point=(\d+) x=([0-9A-F]{16})', raw):
        actual.setdefault(int(qid), []).append(struct.unpack('>d', bytes.fromhex(value))[0])
    results = {}
    for chunk in raw.split('RESULT ')[1:]:
        qid = int(re.search(r'qid=(\d+)', chunk)[1])
        results[qid] = {key: struct.unpack('>d', bytes.fromhex(h))[0]
                        for key, h in re.findall(r'\b(q|sd|c|h)=([0-9A-F]{16})', chunk)}
    new = []
    for query in manifest['queries']:
        qid = query['qid']
        x = actual.get(qid, [])
        if list(map(bits, x)) != list(map(bits, query['values'])) or qid not in results:
            stop(work, state, f'Round {round_number}, qid {qid}: missing/mismatched actual SAS input or result')
        value = unrank(int(query['rank']))
        point = x.index(value)
        hs = [prior.halfgrid.forced(x, query['k'], point, side) for side in (0, 1)]
        h = results[qid]['h']
        matches = [side for side in (0, 1) if abs(hs[side]-h) < 1e-10]
        if len(matches) != 1:
            stop(work, state, f'Round {round_number}, qid {qid}: unresolved forced bins {hs}, oracle {h}')
        row = dict(round=round_number, qid=qid, target_id=query['target_id'], rank=query['rank'],
                   offset=query['offset'], x_hex=query['x_hex'], k=query['k'],
                   selected_bin=query['k']+matches[0], oracle_h=h, candidate_h=hs,
                   bandwidth_error=abs(hs[matches[0]]-h))
        new.append(row)
    state['observations'].extend(new)
    save(work/f'round-{round_number}-observed.json', new)
    for target in state['targets']:
        seen = {}
        for row in state['observations']:
            if row['target_id'] != target['id']:
                continue
            key = int(row['rank'])
            side = row['selected_bin']-target['k']
            if key in seen and side != seen[key]:
                stop(work, state, f'Target {target["id"]}: inconsistent repeated assignment at {key}')
            seen[key] = side
        ordered = sorted(seen.items())
        if any(a[1] > b[1] for a, b in zip(ordered, ordered[1:])):
            stop(work, state, f'Target {target["id"]}: nonmonotonic sampled assignments')
        left = [key for key, side in ordered if side == 0]
        right = [key for key, side in ordered if side == 1]
        if not left or not right:
            stop(work, state, f'Target {target["id"]}: fixed +/-32 window does not bracket a transition')
        target['last_left'], target['first_right'] = str(max(left)), str(min(right))
        if round_number == 7:
            l, r = max(left), min(right)
            if r-l != 1 or [seen.get(k) for k in (l-1, l, r, r+1)] != [0, 0, 1, 1]:
                stop(work, state, f'Target {target["id"]}: final neighbor verification failed')
    state['next_round'] = round_number+1
    if round_number == 7:
        state['status'] = 'complete'
    save(work/'state.json', state)
    print(f'Round {round_number}: {len(new)}/{len(new)} uniquely resolved; total {len(state["observations"])} groups.')
    print('Remaining rank gaps: '+', '.join(str(int(t['first_right'])-int(t['last_left'])) for t in state['targets']))


def predicted_transition(target, generator, decision):
    k, low, high = target['k'], target['low'], target['high']
    middle = int(target['midpoint_rank'])
    left, right = middle-32, middle+32
    if select(low, high, k, unrank(left), generator, decision) != k or select(low, high, k, unrank(right), generator, decision) != k+1:
        return None
    while right-left > 1:
        m = (left+right)//2
        if select(low, high, k, unrank(m), generator, decision) == k:
            left = m
        else:
            right = m
    return right


def report(work):
    state = read(work/'state.json')
    assert state['status'] in ('complete', 'unresolved')
    if state['status'] != 'complete':
        print('BOUNDED SEARCH UNRESOLVED: '+state['reason'])
        return
    offline = read(work/'offline-results.json')
    targets = state['targets']
    rows = []
    for target in targets:
        l, r = int(target['last_left']), int(target['first_right'])
        low, high, k = F(target['low']), F(target['high']), target['k']
        half = F(2*k+1, 2)
        unit = prior.ulp(half, 53)
        rows.append(dict(target_id=target['id'], domain=target['domain'], k=k,
                         low_hex=bits(float(low)), high_hex=bits(float(high)),
                         last_left_hex=bits(unrank(l)), first_right_hex=bits(unrank(r)),
                         last_left_rank=str(l), first_right_rank=str(r),
                         last_left_offset=l-int(target['midpoint_rank']), first_right_offset=r-int(target['midpoint_rank']),
                         last_left_q_ulp53=str((200*(F(unrank(l))-low)/(high-low)-half)/unit),
                         first_right_q_ulp53=str((200*(F(unrank(r))-low)/(high-low)-half)/unit)))
    predictions = []
    scores = []
    for generator, decision in itertools.product(GENERATORS, DECISIONS):
        exact = 0
        for target in targets:
            predicted = predicted_transition(target, generator, decision)
            actual = int(target['first_right'])
            a, b = centers(target['low'], target['high'], generator)[target['k']:target['k']+2]
            predictions.append(dict(generator=generator, decision=decision, target_id=target['id'],
                                    center_k_hex=bits(a), center_next_hex=bits(b),
                                    predicted_first_right_hex=bits(unrank(predicted)) if predicted is not None else 'outside_window',
                                    measured_first_right_hex=bits(unrank(actual)),
                                    rank_error=predicted-actual if predicted is not None else 'outside_window'))
            exact += predicted == actual
        old = next(m['passed'] for m in offline['models'] if m['generator'] == generator and m['decision'] == decision)
        probe_pass = sum(select(targets[o['target_id']]['low'], targets[o['target_id']]['high'], o['k'],
                                unrank(int(o['rank'])), generator, decision) == o['selected_bin'] for o in state['observations'])
        scores.append(dict(generator=generator, decision=decision, old_passed=old,
                           exact_thresholds=exact, queried_groups_passed=probe_pass))
    recurrence = []
    for domain in (0, 1):
        group = sorted([t for t in targets if t['domain'] == domain], key=lambda t:t['k'])
        for a, b in zip(group, group[1:]):
            ra, rb = unrank(int(a['first_right'])), unrank(int(b['first_right']))
            exact_step = (F(a['high'])-F(a['low']))/200
            predicted = ra+float(exact_step)
            recurrence.append(dict(domain=domain, from_k=a['k'], to_k=b['k'],
                                   exact_increment_error=str(F(rb)-F(ra)-exact_step),
                                   stored_add_rank_error=rank(rb)-rank(predicted)))
    translations = []
    for k in (86, 87, 88):
        a = next(t for t in targets if t['domain'] == 0 and t['k'] == k)
        b = next(t for t in targets if t['domain'] == 1 and t['k'] == k)
        delta = F(b['low'])-F(a['low'])
        assert delta == F(b['high'])-F(a['high'])
        ra, rb = unrank(int(a['first_right'])), unrank(int(b['first_right']))
        predicted = ra+float(delta)
        translations.append(dict(k=k, exact_domain_shift=str(delta),
                                 exact_threshold_shift_residual=str(F(rb)-F(ra)-delta),
                                 stored_translate_rank_error=rank(rb)-rank(predicted)))
    summary = dict(status='complete', queried_groups=len(state['observations']),
                   unique_inputs=len({(o['target_id'], o['rank']) for o in state['observations']}),
                   maximum_bandwidth_error=max(o['bandwidth_error'] for o in state['observations']),
                   thresholds=rows, scores=scores, recurrence=recurrence, translations=translations)
    save(work/'threshold-results.json', summary)
    for name, data in [('thresholds.csv', rows), ('model-thresholds.csv', predictions)]:
        with (work/name).open('w', newline='') as out:
            writer = csv.DictWriter(out, fieldnames=list(data[0])); writer.writeheader(); writer.writerows(data)
    print(f'Completed {len(targets)} transitions: {summary["queried_groups"]}/72 groups, {summary["unique_inputs"]} distinct inputs; max h error {summary["maximum_bandwidth_error"]:.6g}.')
    for row in rows:
        print(f'domain={row["domain"]} k={row["k"]}: L={row["last_left_offset"]}, R={row["first_right_offset"]}; qULP=[{row["last_left_q_ulp53"]}, {row["first_right_q_ulp53"]}]')
    for row in sorted(scores, key=lambda r:(-r['exact_thresholds'], -r['queried_groups_passed']))[:8]:
        print(row)
    print('Recurrence:', recurrence)
    print('Translation:', translations)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=('generate', 'observe', 'report'))
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--round', type=int)
    args = parser.parse_args()
    check_frozen()
    if args.action == 'generate':
        generate(args.work, args.round)
    elif args.action == 'observe':
        observe(args.work, args.round)
    else:
        report(args.work)


if __name__ == '__main__':
    main()
