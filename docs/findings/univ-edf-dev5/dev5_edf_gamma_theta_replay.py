from pathlib import Path
from collections import defaultdict
import math,gzip,sys
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
records=defaultdict(list);known=defaultdict(list)
for file in ['gamma-theta','gamma-theta-grid','gamma-theta-est']:
 for line in gzip.open(HERE/('dev5-edf-'+file+'.txt.gz'),'rt').read().splitlines():
  fs=list(map(str.strip,line.split('|')))
  if len(fs) not in [7,8]:continue
  f,n,g,t,x,p,sign=fs[:7];fam,shape=f.split('_');a=float(fs[7]) if len(fs)==8 else float(shape)
  if x=='.' or p=='.':continue
  n=int(n);x=float(x);p=float(p)
  if len(fs)==7:known[f,n,t].append((x,p,sign))
  if not sign and .001<p<.25:records[fam,t].append((n,a,x*(math.sqrt(n) if t=='D' else 1),p))
knots={key:critical(v) for key,v in known.items()}
bases={}
for fam in ['gtheta0','gtheta1','gtheta2','gtheta3']:
 for t in ['D','W-Sq','A-Sq']:
  if fam=='gtheta0':p=[(0,0),(0,.5),(0,1),(1,0),(1,.5),(2,0),(2,.5),(3,0),(3,.5)]
  elif fam=='gtheta1':
   if t=='W-Sq':p=[(0,0),(0,.5),(0,'log'),(1,0),(1,.5),(.5,'log'),(1,'log')]
   elif t=='D':p=[(0,0),(0,.5),(0,1),(1,0),(1,.5),(1,1)]
   else:p=[(i,j) for i in range(3) for j in [0,.5,1]]
  elif fam=='gtheta2':
   if t=='A-Sq':p=[(0,0),(0,1),(1,0),(1,.5),(2,1)]
   else:p=[(0,0),(0,.5),(0,1),(1,0),(1,.5),(1,1),(2,0),(3,.5)]
  else:
   if t=='D':p=[(0,0),(0,.5),(0,1),(0,2),(1,0),(1,.5),(1,3),(2,1)]
   elif t=='W-Sq':p=[(0,0),(0,1),(0,2),(0,3),(1,0),(3,.5),(3,1),(3,2)]
   else:p=[(0,0),(0,1),(0,2),(0,3),(1,0),(1,.5),(1,1),(2,1),(3,.5),(3,2)]
  bases[fam,t]=p
def basis(n,a):return np.array([a**-ap*(1/math.log(n) if npow=='log' else n**-npow) for ap,npow in bases[fam,t]])
result={}
for fam in ['gtheta0','gtheta1','gtheta2','gtheta3']:
 for t in ['D','W-Sq','A-Sq']:
  data=records[fam,t];B=np.array([basis(n,a) for n,a,x,p in data]);X=np.array([x for n,a,x,p in data]);P=np.array([p for n,a,x,p in data]);scale=np.max(abs(B),axis=0);B=B/scale;K=len(scale);C=[]
  for level in levels:
   pts=[]
   if fam in ['gtheta0','gtheta1']:
    for (f,n,tt),v in knots.items():
     if f.startswith(fam) and tt==t and level in v:pts.append((basis(n,float(f.split('_')[1]))/scale,math.log(v[level]*(math.sqrt(n) if t=='D' else 1))))
   if len(pts)>K+4:
    M=np.array([row for row,y in pts]);Y=np.array([y for row,y in pts]);cs=np.linalg.lstsq(M,Y,rcond=1e-11)[0]
   else:
    near=np.argsort(abs(np.log(P/level)))[:max(30,len(P)//100)];cs=np.zeros(K);cs[0]=np.median(np.log(X[near]))
   C.append(cs)
  C=np.array(C);groups=[]
  for i in range(9):
   mask=(P<=levels[i])&(P>levels[i+1]);b=B[mask];y=np.log(X[mask]);w=(P[mask]-levels[i+1])/(levels[i]-levels[i+1]);groups.append((b,y,w))
  def residual(C):
   rr=np.concatenate([np.log(w*np.exp(np.clip(b@C[i],-50,50))+(1-w)*np.exp(np.clip(b@C[i+1],-50,50)))-y for i,(b,y,w) in enumerate(groups)]);return max(abs(rr)),np.dot(rr,rr)
  print(fam,t,'rows',len(B),'initial',residual(C),flush=True)
  for it in range(25):
   H=np.zeros((10*K,10*K));G=np.zeros(10*K)
   for i,(b,y,w) in enumerate(groups):
    v1=w*np.exp(np.clip(b@C[i],-50,50));v2=(1-w)*np.exp(np.clip(b@C[i+1],-50,50));v=v1+v2;r=np.log(v)-y;w1=v1/v;w2=v2/v;s1=slice(i*K,(i+1)*K);s2=slice((i+1)*K,(i+2)*K)
    H[s1,s1]+=b.T@(w1[:,None]**2*b);H[s2,s2]+=b.T@(w2[:,None]**2*b);cross=b.T@((w1*w2)[:,None]*b);H[s1,s2]+=cross;H[s2,s1]+=cross.T;G[s1]+=b.T@(w1*r);G[s2]+=b.T@(w2*r)
   step=np.linalg.lstsq(H,-G,rcond=1e-14)[0].reshape(C.shape);old=residual(C)[1];factor=1
   while residual(C+factor*step)[1]>old and factor>1/128:factor/=2
   C+=factor*step;err=residual(C);print(fam,t,'iteration',it,err,'step',factor,flush=True)
   if err[0]<2e-11:break
  result[fam,t]=(C/scale).tolist();print('COEFFICIENTS .05',fam,t,np.round(C[4]/scale,8),flush=True)

tables={key:np.round(C,8).tolist() for key,C in result.items()}
rng=np.random.default_rng(1317)
def basis(key,n,a):return np.array([a**-ap*(1/math.log(n) if npow=='log' else n**-npow) for ap,npow in bases[key]])
for key,C in list(tables.items()):
 fam,t=key;pts=[]
 for l in gzip.open(HERE/'dev5-edf-gamma-theta-median.txt.gz','rt').read().splitlines():
  fs=list(map(str.strip,l.split('|')))
  if len(fs)!=7:continue
  f,n,ti,x,a,lo,hi=fs
  if f.split('_')[0]!=fam or ['D','W-Sq','A-Sq'][int(ti)-1]!=t or x=='.' or float(lo)>7.999 or float(hi)<1e-6:continue
  n=int(n);pts.append((basis(key,n,float(a)),math.log(float(x)*(math.sqrt(n) if t=='D' else 1))))
 B=np.array([b for b,y in pts]);Y=np.array([y for b,y in pts]);C=np.array(C);fixed=np.ptp(C,axis=0)<1e-6;values=np.median(C,axis=0);inds=np.where(~fixed)[0];y=Y-B[:,fixed]@values[fixed];M=B[:,~fixed];scale=np.linalg.norm(M,axis=0);M=M/scale
 c=np.linalg.lstsq(M,y,rcond=None)[0];best=(sum(abs(M@c-y)<1e-9),c)
 for _ in range(1000):
  sel=rng.choice(len(M),len(inds),replace=False);cc=np.linalg.lstsq(M[sel],y[sel],rcond=None)[0];num=sum(abs(M@cc-y)<1e-9)
  if num>best[0]:best=(num,cc)
 inliers=abs(M@best[1]-y)<1e-9;cf=np.linalg.lstsq(M[inliers],y[inliers],rcond=None)[0]/scale;c=values.copy();c[~fixed]=cf;c=np.round(c,8);tables[key]=[c.tolist()]+C.tolist();print(key,'median',len(pts),'inliers',sum(inliers),'max residual',max(abs(B@c-Y)),c,flush=True)
levels=[.5,.25,.2,.15,.1,.05,.025,.01,.005,.0025,.001]
def predict(key,n,a,x):
 crit=np.exp(np.array(tables[key])@basis(key,n,a))/(math.sqrt(n) if key[1]=='D' else 1)
 if x<crit[0]:return .5,'>'
 if x>crit[-1]:return .001,'<'
 if x==crit[-1]:return .001,''
 if x<crit[1]:return .25,'>'
 for i in range(2,11):
  if x<=crit[i]:return levels[i-1]+(x-crit[i-1])/(crit[i]-crit[i-1])*(levels[i]-levels[i-1]),''
 return .001,'<'
errors=[];count=0;mx=0
for l in gzip.open(HERE/'dev5-edf-gamma-theta-heldout.txt.gz','rt').read().splitlines():
 fs=list(map(str.strip,l.split('|')))
 if len(fs)!=8:continue
 f,n,g,t,x,p,s,a=fs;n=int(n);key=f.split('_')[0],t;pp,ss=predict(key,n,float(a),float(x));count+=1;mx=max(mx,abs(pp-float(p)))
 if abs(pp-float(p))>2e-9 or s!=ss:errors.append((f,n,g,t,p,pp,s,ss))
print('VALIDATION',count,mx,len(errors),errors[:10])

assert not errors
