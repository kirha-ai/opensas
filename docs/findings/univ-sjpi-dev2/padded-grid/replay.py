#!/usr/bin/env python3
"""Reproduce the final rejection and preserve every earlier counterexample."""
from pathlib import Path
import argparse
import json
import subprocess
import sys

HERE=Path(__file__).resolve().parent


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args()
    args.out.mkdir(parents=True,exist_ok=True)
    subprocess.run([sys.executable,str(HERE/'discover.py'),'--out',str(args.out)],check=True)
    actual=json.loads((args.out/'discovery-results.json').read_text())
    expected=json.loads((HERE/'discovery-results.json').read_text())
    assert actual==expected
    assert actual['selected'] is None and not actual['viable_identities']
    by_id={(m['origin'],m['spacing'],m['decision']):m for m in actual['models']}
    for size in [64,80,88]:
        previous=json.loads((HERE/f'discovery{size}-results.json').read_text())
        assert len(previous['models'])==size
        assert previous['old_case_order']==actual['old_case_order']
        assert previous['probe_case_order']==actual['probe_case_order']
        for old in previous['models']:
            now=by_id[(old['origin'],old['spacing'],old['decision'])]
            for field in ['old_passed','probe_passed','exact_thresholds','failed_old','failed_probes']:
                assert old[field]==now[field],(size,field)
    subprocess.run([sys.executable,str(HERE/'audit.py'),'--out',str(args.out)],check=True)
    assert json.loads((args.out/'geometry-audit.json').read_text())==json.loads((HERE/'geometry-audit.json').read_text())
    print('REPLAY PASS: all 184 configurations, all historical failures, 163 geometry checks and exact-tie witnesses reproduce.')
    print('This is a rejected-discovery result, not raw-selector acceptance.')


if __name__=='__main__':
    main()
