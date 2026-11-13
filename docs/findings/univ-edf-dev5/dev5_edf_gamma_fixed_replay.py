from pathlib import Path
import math, gzip
import numpy as np
HERE=Path(__file__).resolve().parent
bases={}
for fam in ['gscale','gshape','gboth']:
 for t in ['D','W-Sq','A-Sq']:
  powers=[(0,0),(0,.5),(0,1),(1,0),(1,1)] if t=='D' else [(0,0),(0,1),(0,2),(1,0),(1,1)]
  if t=='D' and fam=='gscale': powers += [(2,0),(2,1)]
  bases[fam,t]=powers
levels=[.5,.25,.2,.15,.1,.05,.025,.01,.005,.0025,.001]
rows=[]
for l in gzip.open(HERE/'dev5-edf-gamma-knots.txt.gz','rt').read().splitlines():
 fs=list(map(str.strip,l.split('|')))
 if len(fs)!=8:continue
 f,alpha,n,p,t,x,lo,hi=fs
 if float(lo)>7.999 or float(hi)<1e-6:continue
 rows.append((f,float(alpha),int(n),float(p),['D','W-Sq','A-Sq'][int(t)-1],float(x)))
coef={}
for (f,t),powers in bases.items():
 coef[f,t]=[]
 for p in levels:
  pts=[(a,n,math.log(x*(math.sqrt(n) if t=='D' else 1))) for ff,a,n,pp,tt,x in rows if f==ff and t==tt and p==pp]
  m=np.array([[a**-sp*n**-nn for sp,nn in powers] for a,n,y in pts]);y=np.array([y for a,n,y in pts]);c=np.linalg.lstsq(m,y,rcond=None)[0];c=np.round(c,8);err=max(abs(m@c-y));coef[f,t].append(c.tolist());print(f,t,p,len(pts),err,c.tolist())
# Validate the actual fitted shapes, not the generator's target.
def predict(f,t,n,a,x):
 criticals=[math.exp(sum(c*a**-sp*n**-nn for c,(sp,nn) in zip(cs,bases[f,t])))/(math.sqrt(n) if t=='D' else 1) for cs in coef[f,t]]
 if x<criticals[0]:return .5,'>'
 if x<criticals[1]:return .25,'>'
 for i in range(2,11):
  if x<=criticals[i]:return levels[i-1]+(x-criticals[i-1])/(criticals[i]-criticals[i-1])*(levels[i]-levels[i-1]),''
 return .001,'<'
count=0;mx=0;errors=[]
for l in gzip.open(HERE/'dev5-edf-gamma-heldout.txt.gz','rt').read().splitlines():
 fs=list(map(str.strip,l.split('|')))
 if len(fs)!=8:continue
 id,n,g,t,x,p,s,a=fs;fam=next(f for f in ['gscale','gshape','gboth'] if id.startswith(f));pp,ss=predict(fam,t,int(n),float(a),float(x));count+=1;mx=max(mx,abs(pp-float(p)))
 if abs(pp-float(p))>2e-9 or ss!=s:errors.append((id,n,g,t,p,pp,s,ss))
print('VALIDATION',count,mx,len(errors),errors[:10])

assert not errors
