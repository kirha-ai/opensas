import gzip,math,json
from collections import defaultdict
from pathlib import Path

def read(path):
 rows=defaultdict(list)
 text=gzip.open(path,'rt').read() if str(path).endswith('.gz') else Path(path).read_text()
 for line in text.splitlines():
  fs=line.split('|')
  if len(fs)!=7:continue
  fam,n,g,t,x,p,s=map(str.strip,fs)
  if not x or x=='.':continue
  rows[fam,int(n),t].append((float(x),float(p),s))
 return rows

def extract(data):
 pts=sorted((x,p) for x,p,s in data if not s);groups=[]
 for (x,p),(y,q) in zip(pts,pts[1:]):
  if y-x<1e-12:continue
  a=(q-p)/(y-x);b=p-a*x
  if groups and abs(a-groups[-1][0])<abs(a)*1e-6:groups[-1][2]+=1;groups[-1][4]=q
  else:groups.append([a,b,1,p,q])
 groups=[g for g in groups if g[2]>=3]
 knots=[]
 for g,h in zip(groups,groups[1:]):
  a,b,_,p,q=g;aa,bb,*_=h
  x=(bb-b)/(a-aa);level=a*x+b
  knots.append((level,x))
 return groups,knots
def critical(data):
 groups,knots=extract(data)
 levels=[.25,.2,.15,.1,.05,.025,.01,.005,.0025,.001]
 out={}
 for a,b,count,p,q in groups:
  low=max((v for v in levels if v<=q+1e-9),default=None);high=min((v for v in levels if v>=p-1e-9),default=None)
  for level in [high,low]:
   if level is not None:out[level]=(level-b)/a
 return out

def solve(a,b):
 a=[list(row)+[v] for row,v in zip(a,b)];n=len(b)
 for i in range(n):
  j=max(range(i,n),key=lambda j:abs(a[j][i]));a[i],a[j]=a[j],a[i]
  z=a[i][i];a[i]=[v/z for v in a[i]]
  for j in range(n):
   if i!=j:
    z=a[j][i];a[j]=[x-z*y for x,y in zip(a[j],a[i])]
 return [row[-1] for row in a]
def fit(xs,ys,basis):
 a=[[f(x) for f in basis] for x in xs];k=len(basis)
 c=solve([[sum(row[i]*row[j] for row in a) for j in range(k)] for i in range(k)],[sum(row[i]*y for row,y in zip(a,ys)) for i in range(k)])
 return c,max(abs(sum(q*f(x) for q,f in zip(c,basis))-y) for x,y in zip(xs,ys))

ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
r=read(HERE/"dev5-edf-dense.txt.gz");r.update(read(HERE/"dev5-edf-exp-n.txt.gz"));knots={k:critical(v) for k,v in r.items()}

levels=[.25,.2,.15,.1,.05,.025,.01,.005,.0025,.001]
coef={}
for fam in ['exp','exptheta','expboth']:
 for t in ['D','W-Sq','A-Sq']:
  powers=([0,.5,1,2] if fam=='expboth' else [0,.5,2]) if t=='D' else ([0,.5,1] if t=='W-Sq' else [0,1,2,3]) if fam=='expboth' else [0,1]
  print(fam,t,powers)
  cs=[]
  for p in levels:
   ns=sorted(n for f,n,s in knots if f==fam and s==t and p in knots[f,n,s]);ys=[math.log(knots[fam,n,t][p]*(math.sqrt(n-(fam=='exptheta')) if t=='D' else 1)) for n in ns];xs=[n-(fam=='exptheta') for n in ns]
   if len(xs)<len(powers):print('MISSING',p,ns);continue
   c,err=fit(xs,ys,[lambda n,p=p:n**(-p) for p in powers]);print(p,[round(v,8) for v in c],err)
   cs.append([round(v,8) for v in c])
  coef[fam,t]=cs

med={('exp','D'):[-.34884625,-.2237514,.17486795],('exp','W-Sq'):[-2.6056895,.18479393],('exp','A-Sq'):[-.70180186,-.2147402],('exptheta','D'):[-.1880318,-.20652846,.18711928],('exptheta','W-Sq'):[-2.1308363,.21272455],('exptheta','A-Sq'):[-.2555143,-.07775099],('expboth','D'):[-.348134,-.23732181,-.43764886,-.94529455],('expboth','W-Sq'):[-2.5823807,-.40159718,-.41659897],('expboth','A-Sq'):[-.71940969,-4.3586614,26.7976435,-65.225476]}
levels=[.5,.25,.2,.15,.1,.05,.025,.01,.005,.0025,.001]
def predict(f,t,n,x):
 ne=n-(f=='exptheta')
 pw=([0,.5,1,2] if f=='expboth' else [0,.5,2]) if t=='D' else ([0,.5,1] if t=='W-Sq' else [0,1,2,3]) if f=='expboth' else [0,1]
 crit=[math.exp(sum(v*ne**-p for v,p in zip(c,pw)))/(math.sqrt(ne) if t=='D' else 1) for c in [med[f,t]]+coef[f,t]]
 if x<crit[0]:return .5,'>'
 if x<crit[1]:return .25,'>'
 for i in range(2,len(crit)):
  if x<=crit[i]:return levels[i-1]+(x-crit[i-1])/(crit[i]-crit[i-1])*(levels[i]-levels[i-1]),''
 return .001,'<'

for file in [HERE/'dev5-edf-dense.txt.gz', HERE/'dev5-edf-exp-n.txt.gz', HERE/'dev5-edf-exp-heldout.txt.gz']:
 count=0;maxerr=0;errors=0
 for (f,n,t),data in read(file).items():
  if f not in ['exp','expboth','exptheta']:continue
  for x,p,sign in data:
   pp,ss=predict(f,t,n,x);count+=1;maxerr=max(maxerr,abs(pp-p))
   errors+=abs(pp-p)>2e-10 or ss!=sign
 print(file.name,count,'rows, max p error',maxerr,'mismatches',errors)
 assert errors==0
