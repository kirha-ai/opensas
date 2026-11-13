from pathlib import Path
from collections import defaultdict
import math,gzip
import numpy as np
HERE=Path(__file__).resolve().parent
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

levels=np.array([.25,.2,.15,.1,.05,.025,.01,.005,.0025,.001])
rows=defaultdict(list);raw=defaultdict(list)
for file in ['beta','beta-grid']:
 for line in gzip.open(HERE/('dev5-edf-'+file+'.txt.gz'),'rt').read().splitlines():
  fs=list(map(str.strip,line.split('|')))
  if len(fs)!=9:continue
  f,n,g,t,x,p,sign,a,b=fs;n=int(n);x=float(x);p=float(p);a,b=sorted([float(a),float(b)])
  rows[f,n,t].append((x,p,sign))
  if not sign and .001<p<.25:raw[t].append((n,a,b,x*(math.sqrt(n) if t=='D' else 1),p))
knots={key:critical(v) for key,v in rows.items()}
def basis(n,a,b):return np.array([1,1/n,1/n**2,1/a,1/b,1/a**2,1/b**2,1/(a*b),1/(a*n),1/(b*n),1/(a*a*n)])
result={}
for t in ['D','W-Sq','A-Sq']:
 B=np.array([basis(n,a,b) for n,a,b,x,p in raw[t]]);X=np.array([x for n,a,b,x,p in raw[t]]);P=np.array([p for n,a,b,x,p in raw[t]])
 scale=np.max(abs(B),axis=0);B=B/scale;K=len(scale);C=[]
 for level in levels:
  pts=[]
  for (f,n,tt),values in knots.items():
   if tt!=t or level not in values:continue
   _,a,b=f.split('_');pts.append((basis(n,float(a),float(b))/scale,math.log(values[level]*(math.sqrt(n) if t=='D' else 1))))
  M=np.array([row for row,y in pts]);Y=np.array([y for row,y in pts]);C.append(np.linalg.lstsq(M,Y,rcond=None)[0])
 C=np.array(C)
 groups=[]
 for i in range(9):
  mask=(P<=levels[i])&(P>levels[i+1]);b=B[mask];y=np.log(X[mask]);w=(P[mask]-levels[i+1])/(levels[i]-levels[i+1]);groups.append((b,y,w))
 def residual(C):
  return max(max(abs(np.log(w*np.exp(b@C[i])+(1-w)*np.exp(b@C[i+1]))-y)) for i,(b,y,w) in enumerate(groups))
 print(t,'rows',len(B),'initial',residual(C),flush=True)
 for iteration in range(12):
  H=np.zeros((10*K,10*K));G=np.zeros(10*K)
  for i,(b,y,w) in enumerate(groups):
   v1=w*np.exp(b@C[i]);v2=(1-w)*np.exp(b@C[i+1]);v=v1+v2;r=np.log(v)-y;w1=v1/v;w2=v2/v;s1=slice(i*K,(i+1)*K);s2=slice((i+1)*K,(i+2)*K)
   H[s1,s1]+=b.T@(w1[:,None]**2*b);H[s2,s2]+=b.T@(w2[:,None]**2*b);cross=b.T@((w1*w2)[:,None]*b);H[s1,s2]+=cross;H[s2,s1]+=cross.T;G[s1]+=b.T@(w1*r);G[s2]+=b.T@(w2*r)
  step=np.linalg.lstsq(H,-G,rcond=1e-13)[0].reshape(C.shape);C+=step
  err=residual(C);print(t,'iter',iteration,err,flush=True)
  if err<2e-12:break
 result[t]=(C/scale).tolist();print(t,'coeff .05',np.round(C[4]/scale,8),flush=True)

rng=np.random.default_rng(8414)
coefs=result
medians={}
for t in ['D','W-Sq','A-Sq']:
 pts=[]
 for line in gzip.open(HERE/'dev5-edf-beta-median.txt.gz','rt').read().splitlines():
  fs=list(map(str.strip,line.split('|')))
  if len(fs)!=8:continue
  f,n,ti,x,a,b,lo,hi=fs
  if ['D','W-Sq','A-Sq'][int(ti)-1]!=t or float(lo)>7.999 or float(hi)<1e-6:continue
  n=int(n);a,b=sorted([float(a),float(b)]);pts.append(([1,1/n,1/n**2,1/a,1/b,1/a**2,1/b**2,1/(a*b),1/(a*n),1/(b*n),1/(a*a*n)],math.log(float(x)*(math.sqrt(n) if t=='D' else 1))))
 B=np.array([b for b,y in pts]);Y=np.array([y for b,y in pts]);fixed=np.round(coefs[t][4][-3:],8);y=Y-B[:,-3:]@fixed;m=B[:,:8];scale=np.linalg.norm(m,axis=0);m=m/scale;best=(0,None)
 for _ in range(1500):
  ids=rng.choice(len(m),8,replace=False);c=np.linalg.lstsq(m[ids],y[ids],rcond=None)[0];res=abs(m@c-y);count=sum(res<1e-9)
  if count>best[0]:best=(count,c)
 c=best[1];ids=abs(m@c-y)<1e-9;c=np.linalg.lstsq(m[ids],y[ids],rcond=None)[0];c=np.r_[c/scale,fixed];print(t,'continuous-cutoff equalities',best[0],'of',len(pts));medians[t]=np.round(c,8).tolist()

tables={t:[medians[t]]+np.round(result[t],8).tolist() for t in result}
levels=[.5,.25,.2,.15,.1,.05,.025,.01,.005,.0025,.001]
for file in ['beta-heldout','beta-bound-holdout']:
 count=0;maxerr=0;errors=0
 for line in gzip.open(HERE/('dev5-edf-'+file+'.txt.gz'),'rt'):
  fs=list(map(str.strip,line.split('|')))
  if len(fs)!=9:continue
  f,n,g,t,x,p,sign,a,b=fs;n=int(n);a,b=sorted([float(a),float(b)]);x=float(x);p=float(p)
  critical=np.exp(np.array(tables[t])@basis(n,a,b))/(math.sqrt(n) if t=='D' else 1)
  if x<critical[0]:actual,sgn=.5,'>'
  elif x<critical[1]:actual,sgn=.25,'>'
  else:
   actual,sgn=.001,'<'
   for i in range(2,11):
    if x<=critical[i]:actual=levels[i-1]+(x-critical[i-1])/(critical[i]-critical[i-1])*(levels[i]-levels[i-1]);sgn='';break
  maxerr=max(maxerr,abs(actual-p));count+=1;errors+=abs(actual-p)>1e-10 or sign!=sgn
 print(file,count,'rows, max error',maxerr,'mismatches',errors)
 assert not errors
