from pathlib import Path
from collections import defaultdict
rows=defaultdict(list)
for l in __import__('gzip').open(Path(__file__).with_name('dev5-edf-dense.txt.gz'), 'rt').read().splitlines():
 f=l.split('|')
 if len(f)!=7:continue
 fam,n,g,t,x,p,s=map(str.strip,f);rows[fam,int(n),t].append((float(x),float(p),s))
for key,data in rows.items():
 if key[1] not in [20,100,500]:continue
 pts=sorted((x,p) for x,p,s in data if not s);groups=[]
 for (x,p),(y,q) in zip(pts,pts[1:]):
  if y-x<1e-12:continue
  a=(q-p)/(y-x);b=p-a*x
  if groups and abs(a-groups[-1][0])<abs(a)*1e-6:groups[-1][2]+=1;groups[-1][4]=q
  else:groups.append([a,b,1,p,q])
 levels=[.25,.15,.1,.05,.025,.01,.005,.0025,.001]
 knots={}
 for a,b,count,p,q in groups:
  if count<3:continue
  low=max((v for v in levels if v<=q+1e-9),default=None);high=min((v for v in levels if v>=p-1e-9),default=None)
  for v in [high,low]:
   if v is not None:knots[v]=(v-b)/a
 print(key,[(p,round(x,9)) for p,x in sorted(knots.items(),reverse=True)])
