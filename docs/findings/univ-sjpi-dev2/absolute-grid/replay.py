#!/usr/bin/env python3
"""Audit the retained bounded query schedule and all raw SAS observations.

Writes only to a new empty output directory. Does not call SAS, generate new
oracle queries, or overwrite the original /private/tmp oracle source paths.
"""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
import sys

import thresholds
from offline import HERE, check_frozen


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    if args.out.exists() and any(args.out.iterdir()):
        raise ValueError('Replay output directory must be new or empty')
    args.out.mkdir(parents=True, exist_ok=True)
    check_frozen()
    subprocess.run([sys.executable, str(HERE/'offline.py'), '--out', str(args.out)], check=True)
    state = dict(status='active', next_round=0, targets=thresholds.read(HERE/'targets.json'), observations=[])
    thresholds.save(args.out/'state.json', state)
    for n in range(8):
        state = thresholds.read(args.out/'state.json')
        manifest = thresholds.read(HERE/f'round-{n}.json')
        expected = []
        for target in state['targets']:
            center = int(target['midpoint_rank'])
            if n == 0:
                keys = [center-32, center+32]
            else:
                left, right = int(target['last_left']), int(target['first_right'])
                if n == 7:
                    assert right-left == 1
                    keys = [left-1, left, right, right+1]
                else:
                    assert right-left > 1
                    keys = [(left+right)//2]
            for key in keys:
                expected.append(thresholds.make_query(target, key, len(expected)))
        assert manifest['queries'] == expected, f'Round {n} differs from the frozen adaptive schedule'
        for suffix in ('.json', '.sas', '.txt'):
            shutil.copyfile(HERE/f'round-{n}{suffix}', args.out/f'round-{n}{suffix}')
        thresholds.observe(args.out, n)
    thresholds.report(args.out)
    old = thresholds.read(HERE/'threshold-results.json')
    new = thresholds.read(args.out/'threshold-results.json')
    for key in ('queried_groups', 'unique_inputs', 'thresholds', 'scores', 'recurrence', 'translations'):
        assert old[key] == new[key], key
    assert new['maximum_bandwidth_error'] < 1e-10
    print('REPLAY PASS: frozen schedule, actual HEX inputs, 72 assignments, six adjacent thresholds and fingerprints reproduced.')


if __name__ == '__main__':
    main()
