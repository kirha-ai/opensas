#!/usr/bin/env python3
"""Post-measurement arithmetic fingerprint, NOT a new selector candidate.

This does not assign a bin, fit a tolerance, or score a new formula. It checks
one structural interpretation of the measured common translation residual.
The 72 frozen center/decision configurations remain the only scored family.
"""
from pathlib import Path
import argparse
import json
import math
from grids import bits, unrank


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    state = json.loads((args.work/'state.json').read_text())
    assert state['status'] == 'complete'
    rows = []
    for target in state['targets']:
        span = target['high']-target['low']
        padded = target['low']-span
        origin = (padded+target['low'])/2
        l, r = int(target['last_left']), int(target['first_right'])
        shifted = [unrank(key)-origin for key in (l-1, l, r, r+1)]
        rows.append(dict(target_id=target['id'], domain=target['domain'], k=target['k'],
                         padded_low_hex=bits(padded), origin_hex=bits(origin),
                         last_left_hex=bits(unrank(l)), first_right_hex=bits(unrank(r)),
                         shifted_four_hex=list(map(bits, shifted)),
                         adjacent_shifted_values=math.nextafter(shifted[1], math.inf) == shifted[2],
                         two_plateaus=shifted[0] == shifted[1] and shifted[2] == shifted[3] and shifted[1] < shifted[2]))
    report = dict(status='Post-measurement diagnostic only; not an accepted selector or frozen candidate.',
                  expression='padded=RN53(low-RN53(high-low)); origin=RN53(RN53(padded+low)/2); z=RN53(x-origin)',
                  rows=rows)
    (args.work/'origin-fingerprint.json').write_text(json.dumps(report, indent=2)+'\n')
    for row in rows:
        print(f'domain={row["domain"]} k={row["k"]}: origin={row["origin_hex"]} z(L-1,L,R,R+1)={row["shifted_four_hex"]}; adjacent={row["adjacent_shifted_values"]}, two_plateaus={row["two_plateaus"]}')
    print('These six local coincidences do not establish a generic bin rule. No runtime mapping is produced.')


if __name__ == '__main__':
    main()
