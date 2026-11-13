"""Prospective audit; the scale rule is frozen from the prior grid work."""
from pathlib import Path
import json, math, re, struct
root=Path(__file__).parent

def pilot(x):
    n=len(x)
    if n<4:return None
    m=math.fsum(x)/n
    v=math.fsum((t-m)**2 for t in x)/(n-1)
    if v<=0:return None
    skew=n*math.fsum((t-m)**3 for t in x)/((n-1)*(n-2)*v**1.5)
    kurt=n*(n+1)*math.fsum((t-m)**4 for t in x)/((n-1)*(n-2)*(n-3)*v*v)-3*(n-1)**2/((n-2)*(n-3))
    denominator=1.5*skew*skew-kurt
    if denominator<=0:return None
    total=(6+3*kurt-3*skew*skew)/denominator
    if total<=0:return None
    r2=skew*skew*(total+2)**2/(16*(total+1)+skew*skew*(total+2)**2)
    if not 0<=r2<1:return None
    imbalance=math.copysign(math.sqrt(r2),skew)
    width=2*math.sqrt(v*(total+1)/(1-r2))
    location=m-width*(1-imbalance)/2
    return {'width':width,'location':location,
            'sigma0':max(x)-min(x)+min(.002,.1*(width-(max(x)-min(x)))),
            'theta0':min(x)-min(.001,.1*(min(x)-location))}

rows=[]
for name in ['prospective-power','initialization-edges']:
    cases=json.loads((root/(name+'-inputs.json')).read_text())
    inputs={};params={}
    for line in (root/(name+'.log')).read_text().splitlines():
        if line.startswith('DEV3_SAMPLE_CASE '):sample=line.split()[1];inputs[sample]=[]
        m=re.fullmatch(r'DEV3_SAMPLE\s+([0-9A-F]{16})',line)
        if m:inputs[sample].append(struct.unpack('>d',bytes.fromhex(m[1]))[0])
        if line.startswith('DEV3_CASE '):case=line.split()[1];params[case]={}
        m=re.fullmatch(r'DEV3_PARAMETER (Theta|Sigma|Alpha)\s+([0-9A-F]{16})',line)
        if m:params[case][m[1].lower()]=struct.unpack('>d',bytes.fromhex(m[2]))[0]
    for c in cases:
        x=inputs[c['id']];p=params[c['id']];m=pilot(x)
        row={**c,'samples':x,'parameters':p,'pilot':m}
        if c['theta'] is not None:
            # Keep the original prospective prediction alongside the revised
            # fixed-alpha range fallback and conditional shape-admissibility
            # policy. Do not erase counterexamples from the first experiment.
            row['original_predicted_curve']=m is not None and m['sigma0']>max(x)-c['theta']
            sigma=None
            if len(x)>=4 and max(x)>min(x):
                sigma=m['sigma0'] if m else max(x)-min(x)+.002 if c['alpha'] is not None else None
            feasible=sigma is not None and sigma>max(x)-c['theta']
            if feasible and c['alpha'] is None:
                y=[(v-c['theta'])/sigma for v in x]
                mean=math.fsum(y)/len(y)
                variance=math.fsum((v-mean)**2 for v in y)/(len(y)-1)
                feasible=mean*(1-mean)>variance
            row['helper_predicted_curve']=feasible
            row['helper_sigma']=sigma
            if feasible:
                a=c['alpha'] if c['alpha'] is not None else -len(x)/math.fsum(math.log((t-c['theta'])/sigma) for t in x)
                row['predicted_alpha']=a
                if p:
                    row['sigma_residual']=p['sigma']-sigma
                    row['alpha_residual']=p['alpha']-a
        elif m and p:
            row['theta_residual']=p['theta']-m['theta0']
            row['sigma_residual']=p['sigma']-m['sigma0']
        rows.append(row)
        print(c['id'],c['group'], 'SAS',p, 'residuals',{k:row[k] for k in row if k.endswith('residual')})
(root/'prospective-power-audit.json').write_text(json.dumps(rows,indent=2,allow_nan=False)+'\n')
print('Fixed-theta original counterexamples',[r['id'] for r in rows if r['theta'] is not None and r['original_predicted_curve']!=bool(r['parameters'])])
print('Fixed-theta helper counterexamples',[r['id'] for r in rows if r['theta'] is not None and r['helper_predicted_curve']!=bool(r['parameters'])])
