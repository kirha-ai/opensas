#!/usr/bin/env python3
"""Geometry-only audit of the rejected best padded-grid model.

Passing geometry is NOT bin-decision acceptance. No oracle labels are used to
change the model, choose a tie per index, or produce a runtime lookup.
"""
from collections import Counter
from pathlib import Path
import argparse
import json
from discover import old, all_samples, PARENT
from model import counts, padded_index

IDENTITY = ('fingerprint', 'original_range', 'ratio_one_even_extended64')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    samples = dict(all_samples())
    rows = []
    for name, values in samples.items():
        p, indices, trimmed = counts(values, *IDENTITY)
        padded = Counter(indices)
        after = Counter({j-100:n for j,n in padded.items()})
        n = len(values)
        before_sum = sum(j*c for j,c in padded.items())
        after_sum = sum(j*c for j,c in after.items())
        before_ss = n*sum(j*j*c for j,c in padded.items())-before_sum**2
        after_ss = n*sum(j*j*c for j,c in after.items())-after_sum**2
        before_dist = Counter()
        after_dist = Counter()
        for i,ci in padded.items():
            for j,cj in padded.items():
                before_dist[abs(i-j)] += ci*cj
        for i,ci in after.items():
            for j,cj in after.items():
                after_dist[abs(i-j)] += ci*cj
        imin = padded_index(min(values),min(values),max(values),*IDENTITY)
        imax = padded_index(max(values),min(values),max(values),*IDENTITY)
        assert imin==100 and imax==300 and sum(trimmed)==n
        assert before_sum-after_sum==100*n and before_ss==after_ss and before_dist==after_dist
        rows.append(dict(name=name,n=n,conserved=sum(trimmed),min_index=imin,max_index=imax,
                         mean_shift_numerator=before_sum-after_sum,variance_numerator=before_ss,
                         variance_preserved=True,pair_distance_histogram_preserved=True,
                         origin=p['origin'],upper=p['upper'],step=p['step']))
    witnesses = []
    records = {r['name']:r for r in old.load_old()}
    for name in ('dev2-sjpi-halfgrid-profile:7','dev2-sjpi-halfgrid:1','dev2-sjpi-halfgrid:13'):
        r=records[name];values=samples[name];p,indices,bins=counts(values,*IDENTITY)
        point=values.index(r['x']);predicted=indices[point]-100
        h=old.prior.halfgrid.forced(values,r['k'],point,predicted-r['k'])
        witnesses.append(dict(name=name,low=r['low'],high=r['high'],x=r['x'],
                              origin=p['origin'],shifted_x=r['x']-p['origin'],
                              exact_padded_q=(r['x']-p['origin'])/(p['upper']-p['origin'])*400,
                              predicted_padded_bin=indices[point],oracle_padded_bin=r['observed_bin']+100,
                              predicted_bandwidth=h,oracle_bandwidth=r['oracle_h']))
    result=dict(status='Geometry passes; raw decisions remain rejected.',identity=IDENTITY,
                audited_samples=len(rows),rows=rows,exact_tie_witnesses=witnesses)
    args.out.mkdir(parents=True,exist_ok=True)
    (args.out/'geometry-audit.json').write_text(json.dumps(result,indent=2)+'\n')
    print(f'{len(rows)}/163 conserve counts, map extrema to 100/300, preserve exact variance numerator and pair-distance counts after common shift 100.')
    for r in witnesses:print(r)


if __name__=='__main__':
    main()
