#!/usr/bin/env python3
from pathlib import Path
import argparse
import importlib.util
import itertools
import json
import struct
import sys

HERE = Path(__file__).resolve().parent
PARENT = HERE.parent
sys.path.insert(0, str(PARENT/'absolute-grid'))
spec = importlib.util.spec_from_file_location('old_absolute_offline', PARENT/'absolute-grid'/'offline.py')
old = importlib.util.module_from_spec(spec)
spec.loader.exec_module(old)
from grids import unrank, bits
from model import ORIGINS, SPACINGS, DECISIONS, padded_index, parameters, counts


def all_samples():
    samples = []
    for stem, rows, actual, stats, cs in old.prior.halfgrid.batches():
        samples.extend((stem+':'+str(r['id']), actual[r['id']]) for r in rows)
    for r in json.loads((PARENT/'extended-precision'/'heldouts-inputs.json').read_text()):
        samples.append(('heldouts:'+str(r['id']), r['values']))
    assert len(samples) == 163
    return samples


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    records = old.load_old()
    state = json.loads((PARENT/'absolute-grid'/'state.json').read_text())
    assert state['status'] == 'complete' and len(state['observations']) == 72
    observations = []
    for o in state['observations']:
        t = state['targets'][o['target_id']]
        observations.append(dict(name=f'threshold:{o["round"]}:{o["qid"]}', low=t['low'], high=t['high'],
                                 x=unrank(int(o['rank'])), observed_bin=o['selected_bin'], k=o['k']))
    models = []
    samples = all_samples()
    for origin, spacing, decision in itertools.product(ORIGINS, SPACINGS, DECISIONS):
        failed_old, failed_probes = [], []
        for r in records:
            predicted = padded_index(r['x'], r['low'], r['high'], origin, spacing, decision)-100
            if predicted != r['observed_bin']:
                failed_old.append(dict(name=r['name'], predicted=predicted, observed=r['observed_bin']))
        for r in observations:
            predicted = padded_index(r['x'], r['low'], r['high'], origin, spacing, decision)-100
            if predicted != r['observed_bin']:
                failed_probes.append(dict(name=r['name'], predicted=predicted, observed=r['observed_bin']))
        exact_thresholds = 0
        for t in state['targets']:
            l, r = unrank(int(t['last_left'])), unrank(int(t['first_right']))
            il = padded_index(l,t['low'],t['high'],origin,spacing,decision)-100
            ir = padded_index(r,t['low'],t['high'],origin,spacing,decision)-100
            exact_thresholds += il == t['k'] and ir == t['k']+1
        metadata = []
        metadata_failures = []
        if not failed_old and not failed_probes and exact_thresholds == 6:
            for name, values in samples:
                try:
                    p, indices, bins = counts(values, origin, spacing, decision)
                    ilo = padded_index(min(values),min(values),max(values),origin,spacing,decision)
                    ihi = padded_index(max(values),min(values),max(values),origin,spacing,decision)
                    if ilo != 100 or ihi != 300:
                        raise ValueError(f'extrema map to {ilo}/{ihi}')
                    metadata.append(dict(name=name, n=len(values), conserved=sum(bins),
                                         min_index=ilo, max_index=ihi, origin_hex=bits(p['origin']),
                                         upper_hex=bits(p['upper']), step_hex=bits(p['step']),
                                         nonzero_bins=[(i,n) for i,n in enumerate(bins) if n]))
                except ValueError as error:
                    metadata_failures.append(dict(name=name, reason=str(error)))
        viable = not failed_old and not failed_probes and exact_thresholds == 6 and not metadata_failures
        models.append(dict(origin=origin,spacing=spacing,decision=decision,
                           old_passed=163-len(failed_old),probe_passed=72-len(failed_probes),
                           exact_thresholds=exact_thresholds,failed_old=failed_old,failed_probes=failed_probes,
                           metadata=metadata,metadata_failures=metadata_failures,viable=viable))
    assert len(models) == 184
    viable = [m for m in models if m['viable']]
    report = dict(old_count=163,probe_count=72,threshold_count=6,models=models,
                  viable_identities=[{k:m[k] for k in ('origin','spacing','decision')} for m in viable],
                  selected={k:viable[0][k] for k in ('origin','spacing','decision')} if viable else None)
    args.out.mkdir(parents=True,exist_ok=True)
    (args.out/'discovery-results.json').write_text(json.dumps(report,indent=2)+'\n')
    for m in sorted(models,key=lambda m:(-m['old_passed'],-m['probe_passed']))[:12]:
        print(m['origin'],m['spacing'],m['decision'],f'old={m["old_passed"]}/163 probes={m["probe_passed"]}/72 thresholds={m["exact_thresholds"]}/6 metadata={len(m["metadata"])} viable={m["viable"]}')
    print('Viable:',report['viable_identities'])
    print('Selected by frozen tuple order:',report['selected'])


if __name__ == '__main__':
    main()
