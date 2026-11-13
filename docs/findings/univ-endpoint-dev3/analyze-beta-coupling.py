"""Independent conditional score roots; no optimizer or case-fitting constants."""
from pathlib import Path
import json,math,re,struct
root=Path(__file__).parent

def read(name):
    samples={};params={}
    for line in (root/(name+'.log')).read_text().splitlines():
        if line.startswith('DEV3_SAMPLE_CASE '):sample=line.split()[1];samples[sample]=[]
        m=re.fullmatch(r'DEV3_SAMPLE\s+([0-9A-F]{16})',line)
        if m:samples[sample].append(struct.unpack('>d',bytes.fromhex(m[1]))[0])
        if line.startswith('DEV3_CASE '):case=line.split()[1];params[case]={}
        m=re.fullmatch(r'DEV3_PARAMETER (Theta|Sigma|Alpha|Beta)\s+([0-9A-F]{16})',line)
        if m:params[case][m[1].lower()]=struct.unpack('>d',bytes.fromhex(m[2]))[0]
    return samples,params

def psi(x):
    value=0.
    while x<16:value-=1/x;x+=1
    r=1/x**2
    return value+math.log(x)-.5/x-r*(1/12-r*(1/120-r*(1/252-r*(1/240-r/132))))

def shape(x,sigma):
    logmean=math.fsum(math.log(v/sigma) for v in x)/len(x)
    score=lambda a:psi(a+1.5)-psi(a)+logmean
    lo=1e-9;hi=1.
    while score(hi)>0:hi*=2
    for _ in range(90):
        mid=(lo+hi)/2
        if score(mid)>0:lo=mid
        else:hi=mid
    return (lo+hi)/2

def scale(x,a):
    score=lambda s:-a+.5*math.fsum(v/(s-v) for v in x)/len(x)
    lo=max(x)*(1+1e-12);hi=2*lo
    while score(hi)>0:hi*=2
    for _ in range(90):
        mid=(lo+hi)/2
        if score(mid)>0:lo=mid
        else:hi=mid
    return (lo+hi)/2

samples,params=read('beta-coupling');rows=[]
for c in json.loads((root/'beta-coupling-inputs.json').read_text()):
    x=samples[c['id']];p=params[c['id']];r={**c,'parameters':p,'returned':bool(p)}
    if c['kind']=='scale-only':
        expected=scale(x,c['alpha']);r['conditional_sigma']=expected
        if p:r['normalized_sigma_error']=(p['sigma']-expected)/c['scale']
    elif c['kind']=='shape-only' and p:
        expected=shape(x,p['sigma']);r['conditional_alpha']=expected;r['alpha_error']=p['alpha']-expected
    elif c['kind']=='joint' and p:
        r['normalized_sigma']=p['sigma']/c['scale']
    rows.append(r)
(root/'beta-coupling-audit.json').write_text(json.dumps(rows,indent=2)+'\n')
print('Joint outcomes',[(r['scale'],r['returned']) for r in rows if r['kind']=='joint'])
print('Conditional returned',sum(r['returned'] for r in rows if r['kind']!='joint'),'of',sum(r['kind']!='joint' for r in rows))
print('Max normalized sigma error',max(abs(r['normalized_sigma_error']) for r in rows if 'normalized_sigma_error' in r))
print('Max alpha error',max(abs(r['alpha_error']) for r in rows if 'alpha_error' in r))
_,params=read('power-conditional-controls');power=[]
for c in json.loads((root/'power-conditional-controls-inputs.json').read_text()):
    p=params[c['id']];r={**c,'parameters':p}
    if p:r['conditional_alpha']=-len(c['values'])/math.fsum(math.log((v-p['theta'])/p['sigma']) for v in c['values']);r['alpha_error']=p['alpha']-r['conditional_alpha']
    power.append(r)
(root/'power-conditional-controls-audit.json').write_text(json.dumps(power,indent=2)+'\n')
print('Power fixed-width returned',sum(bool(r['parameters']) for r in power),'of',len(power))
print('Power max shape error',max(abs(r['alpha_error']) for r in power if 'alpha_error' in r))
