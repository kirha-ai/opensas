import numpy as np, math
from pathlib import Path
rng=np.random.default_rng(129571);n=200;r=np.arange(1,n+1,dtype=np.float64);left=np.arange(n)[None,:]<np.arange(n)[:,None]
den=n*(n-1)*(n-2)*(n-3)*(n-4)
def stat(y):
 q=1+np.sum(left & (y[None,:]<y[:,None]),axis=1)
 a=np.sum((q-1)*(q-2));b=np.sum((r-1)*(r-2)*(y-1)*(y-2));c=np.sum((r-2)*(y-2)*(q-1))
 d=30*((n-2)*(n-3)*a+b-2*(n-2)*c)/den
 return math.pi**4*((n-1)*d/60+1/72)
cases=[]
for nominal in [.3,.55,1.1,2.95,10.3]:
 boundary=nominal + math.pi**4/72 - 1.3529
 y=rng.permutation(r);z=stat(y);best={-1:(float('inf'),None,None),1:(float('inf'),None,None)}
 for k in range(70000):
  a,b=rng.choice(n,2,replace=False);y[a],y[b]=y[b],y[a];v=stat(y);side=1 if v>boundary else -1
  if abs(v-boundary)<best[side][0]:best[side]=(abs(v-boundary),y.copy(),v)
  if abs(v-boundary)<=abs(z-boundary):z=v
  else:y[a],y[b]=y[b],y[a]
 for side,(distance,vals,z) in best.items():
  print(boundary,side,distance,z,flush=True);cases.append((boundary,side,vals))
s='options linesize=240 pagesize=10000; data d; input g n x y; datalines;\n'
for g,(_,_,y) in enumerate(cases,1):
 for x,v in enumerate(y,1):s+=f'{g} {n} {x} {int(v)}\n'
s+=';\nods exclude all;ods output HoeffdingCorr=h;proc corr data=d hoeffding;by g n;var x;with y;run;\nods exclude none;data _null_;set h;file print;put "ROW " g best12. n best12. x e25.17 Px e25.17;run;\n'
Path('/private/tmp/dev5-hoeffding-final-boundaries.sas').write_text(s)
