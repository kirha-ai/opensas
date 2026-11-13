"""Audit candidate initialization/FD hypotheses, independently of Zig fitting.

Uses actual HEX16 input observations and output estimates. Conditional shape
roots are solved from the analytical beta score at each returned endpoint.
"""
from pathlib import Path
import json, math, re, struct, sys
root=Path(__file__).parent

def psi(x):
    value=0.
    while x<16:
        value-=1/x
        x+=1
    r=1/x**2
    return value+math.log(x)-.5/x-r*(1/12-r*(1/120-r*(1/252-r*(1/240-r/132))))

def conditional_shape(logmean,b):
    score=lambda a:psi(a+b)-psi(a)+logmean
    lo=1e-10;hi=1.
    while score(hi)>0:
        hi*=2
        assert hi<1e12,'shape root not bracketed'
    for _ in range(90):
        mid=(lo+hi)/2
        if score(mid)>0:lo=mid
        else:hi=mid
    result=(lo+hi)/2
    assert abs(score(result))<1e-10
    if b==1:assert abs(result+1/logmean)<1e-9*(1+result)
    return result

def moment_width(x):
    n=len(x)
    mean=math.fsum(x)/n
    variance=math.fsum((v-mean)**2 for v in x)/(n-1)
    skew=n*math.fsum((v-mean)**3 for v in x)/((n-1)*(n-2)*variance**1.5)
    kurt=n*(n+1)*math.fsum((v-mean)**4 for v in x)/((n-1)*(n-2)*(n-3)*variance**2)-3*(n-1)**2/((n-2)*(n-3))
    total=(6+3*kurt-3*skew*skew)/(1.5*skew*skew-kurt)
    r2=skew*skew*(total+2)**2/(16*(total+1)+skew*skew*(total+2)**2)
    if total<=0 or not 0<=r2<1:return None
    return 2*math.sqrt(variance*(total+1)/(1-r2))

def constrained_scale(x,b,floor):
    maximum=max(x)
    meanlog=math.fsum(math.log(v) for v in x)/len(x)
    if b<=1:return floor if floor>maximum else None
    def score(sigma):
        a=conditional_shape(meanlog-math.log(sigma),b)
        return -a+(b-1)*math.fsum(v/(sigma-v) for v in x)/len(x)
    lo=max(floor,maximum*(1+1e-12))
    if score(lo)<=0:return lo
    hi=lo*2
    for _ in range(100):
        if score(hi)<0:break
        hi*=2
    else:return None
    for _ in range(70):
        mid=(lo+hi)/2
        if score(mid)>0:lo=mid
        else:hi=mid
    return (lo+hi)/2

allrows=[]
for name in ['scale-grid','controlled-grid']:
    cases=json.loads((root/(name+'-inputs.json')).read_text())
    inputs={};params={}
    for line in (root/(name+'.log')).read_text().splitlines():
        if line.startswith('DEV3_SAMPLE_CASE '): samplecase=line.split()[1];inputs[samplecase]=[]
        m=re.fullmatch(r'DEV3_SAMPLE\s+([0-9A-F]{16})',line)
        if m:inputs[samplecase].append(struct.unpack('>d',bytes.fromhex(m[1]))[0])
        if line.startswith('DEV3_CASE '):case=line.split()[1];params[case]={}
        m=re.fullmatch(r'DEV3_PARAMETER (Theta|Sigma|Alpha|Beta)\s+([0-9A-F]{16})',line)
        if m:params[case][m[1].lower()]=struct.unpack('>d',bytes.fromhex(m[2]))[0]
    assert len(params)==len(cases)
    for case in cases:
        x=inputs[case['id']];p=params[case['id']]
        assert len(x)==case['n']*case.get('copies',1)
        span=max(x)-min(x);box=span+.002
        row={**case,'returned':bool(p),'parameters':p,'sample_min':min(x),'sample_max':max(x),'sample_range':span,'box_sigma':box,'box_feasible':box>max(x)}
        width=moment_width(x)
        if width is not None:
            sigma0=span+min(.002,.1*(width-span))
            row.update(moment_width=width,moment_candidate=sigma0,moment_candidate_feasible=sigma0>max(x))
            predicted=constrained_scale(x,case['fitbeta'] if case['fitbeta'] is not None else 1,sigma0)
            row.update(scale_floor_prediction=predicted)
        allrows.append(row)
        if not p:continue
        theta,sigma,a=(p[k] for k in ['theta','sigma','alpha']);b=p.get('beta',1.)
        assert theta==0
        if case['fitbeta'] is not None: assert b==case['fitbeta']
        y=[(v-theta)/sigma for v in x]
        assert all(0<t<1 for t in y)
        logmean=sum(math.log(t) for t in y)/len(y)
        best=conditional_shape(logmean,b)
        shape_score=psi(a+b)-psi(a)+logmean
        scale_score=(-a+(b-1)*sum(t/(1-t) for t in y)/len(y))/sigma
        h_forward=math.sqrt(sys.float_info.epsilon)*(1+abs(sigma))
        h_central=sys.float_info.epsilon**(1/3)*(1+abs(sigma))
        if width is not None:
            row.update(moment_candidate_residual=sigma-sigma0)
            if predicted is not None:row.update(scale_floor_fit_residual=(sigma-predicted)/case['scale'])
        row.update(sigma_minus_range=sigma-span,box_residual=sigma-box,normalized_sigma=sigma/case['scale'],conditional_alpha=best,alpha_residual=a-best,shape_score_per_observation=shape_score,scale_score_per_observation=scale_score,upper_gap=sigma-max(x),default_forward_step=h_forward,default_central_step=h_central,central_probe_inside_support=sigma-h_central>max(x))
(root/'scale-grid-audit.json').write_text(json.dumps(allrows,indent=2,allow_nan=False)+'\n')
for r in allrows:
    print(r['id'],r['group'],r['n'],r['a'],r.get('copies',1),'beta',r['fitbeta'],'scale',f"{r['scale']:.8g}",'box',r['box_feasible'],'NO CURVE' if not r['returned'] else f"sigma/range={r['parameters']['sigma']/r['sample_range']:.10g} delta={r['sigma_minus_range']:.10g} shape-residual={r['alpha_residual']:.4g}")
print('Total cases',len(allrows),'returned',sum(r['returned'] for r in allrows))
print('Box-presence counterexamples',[r['id'] for r in allrows if r['returned']!=r['box_feasible']])
print('Largest conditional shape residual',max(abs(r['alpha_residual']) for r in allrows if r['returned']))
print('Returned curves with default central step outside support',[r['id'] for r in allrows if r['returned'] and not r['central_probe_inside_support']])

print('Moment candidate power presence counterexamples',[r['id'] for r in allrows if r['family']=='power' and r['returned']!=r.get('moment_candidate_feasible')])
print('Moment candidate power max sigma residual',max(abs(r['moment_candidate_residual']) for r in allrows if r['family']=='power' and r['returned']))
for r in allrows:
    if r['family']=='beta':print('beta candidate',r['id'],'b',r['fitbeta'],'scale',r['scale'],'feasible',r.get('moment_candidate_feasible'),'returned',r['returned'],'delta',r.get('moment_candidate_residual'))

print('Scale-floor prediction presence counterexamples',[r['id'] for r in allrows if r['returned']!=(r.get('scale_floor_prediction') is not None)])
print('Largest scale-floor normalized sigma residual',max(abs(r['scale_floor_fit_residual']) for r in allrows if r['returned'] and 'scale_floor_fit_residual' in r))

power_rows=[r for r in allrows if r['family']=='power']
assert len(power_rows)==53
assert all(r['returned']==r['moment_candidate_feasible'] for r in power_rows)
assert max(abs(r['moment_candidate_residual']) for r in power_rows if r['returned'])<1e-12
# Assertions validate this retained experiment, not arbitrary future inputs.
# In particular the beta failure counterexample is not removed or overridden.
