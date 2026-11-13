"""Independent direct likelihood/score audit of M9's HEX16 ODS estimates.

Only standard-library arithmetic; no optimizer code, fitted case constants,
or helper-produced parameter values. Regenerate with python3 this_file.py.
"""
from pathlib import Path
import json
import math
import re
import struct

root = Path(__file__).parent
cases = {}
for line in (root/'solver-diagnostics.log').read_text().splitlines():
    if line.startswith('DEV3_CASE '):
        case = line.split()[1]
        cases[case] = {}
    m = re.fullmatch(r'DEV3_PARAMETER (Theta|Sigma|Alpha)\s+([0-9A-F]{16})', line)
    if m:
        cases[case][m[1].lower()] = struct.unpack('>d', bytes.fromhex(m[2]))[0]

rows = []
for case, p in cases.items():
    row = {'case':case,'curve_returned':bool(p),'parameters':p}
    rows.append(row)
    if not p: continue
    theta, sigma, alpha = (p[k] for k in ('theta','sigma','alpha'))
    fields = case.split('_')
    if fields[0] == 'power':
        kind = fields[1]
        offset, scale = {'base':(0,1),'scaled':(0,10),'small':(0,.1),'translated':(5,1)}[kind]
        x = [offset+scale*((i-.375)/41.25)**2 for i in range(1,42)]
        y = [v-theta for v in x]
        n = len(y)
        logs = sum(math.log(v) for v in y)
        ll = n*math.log(alpha)-n*alpha*math.log(sigma)+(alpha-1)*logs
        scores = {'theta':-(alpha-1)*sum(1/v for v in y),
                  'sigma':-n*alpha/sigma, 'alpha':n/alpha+logs-n*math.log(sigma)}
        row.update(log_likelihood=ll, scores=scores,
                   upper_gap=theta+sigma-max(x), lower_gap=min(x)-theta,
                   normalized_parameters={'theta':(theta-offset)/scale,'sigma':sigma/scale,'alpha':alpha})
        if fields[2]=='scale':
            boundary=max(y)
            boundary_alpha=-n/sum(math.log(v/boundary) for v in y)
            boundary_ll=n*math.log(boundary_alpha)-n*boundary_alpha*math.log(boundary)+(boundary_alpha-1)*logs
            row.update(boundary_likelihood_gain=boundary_ll-ll)
    else:
        shift = int(fields[1].removeprefix('shift'))
        offset, scale = {'base':(0,1),'scaled':(0,10),'small':(0,.1),'translated':(5,1)}[fields[2]]
        x=[offset+scale*(v+shift) for v in [1,2,3,4,6,8,10,15]]
        y=[v-theta for v in x]
        n=len(x)
        gaps=[sigma-alpha*v for v in y]
        logsum=sum(math.log(gap/sigma) for gap in gaps)
        ratio=sum(v/gap for v,gap in zip(y,gaps))
        ll=-n*math.log(sigma)+(1/alpha-1)*logsum
        scores={'alpha':-logsum/(alpha*alpha)-(1/alpha-1)*ratio,
                'sigma':-n/sigma+(1-alpha)*ratio/sigma}
        # A feasible scale decrease must improve the objective for alpha>1.
        next_sigma=sigma-0.1*min(gaps)
        next_ll=-n*math.log(next_sigma)+(1/alpha-1)*sum(math.log((next_sigma-alpha*v)/next_sigma) for v in y)
        row.update(log_likelihood=ll,scores=scores,upper_gap=sigma/alpha-max(y),
                   feasible_scale_decrease_gain=next_ll-ll,
                   normalized_parameters={'theta':(theta-offset)/scale,'sigma':sigma/scale,'alpha':alpha})

assert all(cases[f'power_base_{mode}_{limit}'] == cases[f'power_base_{mode}_1']
           for mode in ['scale','both','theta'] for limit in [2,20,1000])
(root/'score-audit.json').write_text(json.dumps(rows,indent=2,allow_nan=False)+'\n')
for r in rows:
    if not r['curve_returned']:
        print(r['case'],'NO CURVE')
    elif not r['case'].startswith('power_base_') or r['case'].endswith('_1'):
        print(r['case'],r['normalized_parameters'],'scores',r['scores'])

# Compare every available common parameter in the power/beta(beta=1) matrix.
equivalent={(i,kind,mode):{} for i in range(6) for kind in ['power','beta'] for mode in ['scale','both','theta']}
current=None
for line in (root/'likelihood-equivalence.txt').read_text().splitlines():
    m=re.fullmatch(r'case (\d+) (power|beta) (scale|both|theta)',line)
    if m: current=(int(m[1]),m[2],m[3])
    m=re.match(r' x\s+1\s+(?:PowerFunction|Beta)\s+\S+\s+(Theta|Sigma|Alpha)\s+([-+.0-9Ee]+)\s*$',line)
    if m and current: equivalent[current][m[1]]=float(m[2])
comparisons=[]
for i in range(6):
    for mode in ['scale','both','theta']:
        a=equivalent[i,'power',mode]; b=equivalent[i,'beta',mode]
        assert a==b,(i,mode,a,b)
        comparisons.append({'sample':i,'endpoints':mode,'both_return_curve':bool(a),'power':a,'beta_shape_two_fixed_one':b})
(root/'equivalence-audit.json').write_text(json.dumps(comparisons,indent=2)+'\n')
print('Power/beta equivalence: all',len(comparisons),'pairs match at retained ODS decimal precision')
