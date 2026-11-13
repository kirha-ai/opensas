from pathlib import Path
import random,math,heapq
r=random.Random(991783)
def coefficient(x,y,f):
 n=sum(f);a=b=c=0
 for xx,yy,ff in zip(x,y,f):
  rx=.5+sum(w*(u<xx)+w*.5*(u==xx) for u,w in zip(x,f))
  ry=.5+sum(w*(v<yy)+w*.5*(v==yy) for v,w in zip(y,f))
  q=.75+sum(w*((u<xx and v<yy)+.25*(u==xx and v==yy)+.5*((u==xx and v<yy)or(u<xx and v==yy))) for u,v,w in zip(x,y,f))
  a+=ff*(q-1)*(q-2);b+=ff*(rx-1)*(rx-2)*(ry-1)*(ry-2);c+=ff*(rx-2)*(ry-2)*(q-1)
 return 30*((n-2)*(n-3)*a+b-2*(n-2)*c)/(n*(n-1)*(n-2)*(n-3)*(n-4))
cases=[]
for k in range(450):
 n=r.choice([5,6,7,9,11,17,23,31,47,80]);x=list(range(n));y=x.copy();r.shuffle(y);f=[1]*n
 if k%4==0:x=[v//3 for v in x];y=[v//4 for v in y]
 if k%4==1:f=[r.randrange(1,5) for _ in x]
 if k%4==2:
  y=x.copy()
  for j in range(r.randrange(1,n)):
   a,b=r.sample(range(n),2);y[a],y[b]=y[b],y[a]
 cases.append((x,y,f))
# Search fresh permutations for close probes on BOTH sides of every inferred branch.
nearest={ (b,side):[] for b in [.3,.55,1.1,2.95,10.3] for side in [-1,1] }
for k in range(14000):
 n=31;x=list(range(n));y=x.copy()
 for j in range(r.randrange(1,45)):
  a,b=r.sample(range(n),2);y[a],y[b]=y[b],y[a]
 # Untied ranks, direct bivariate rank count.
 a=b=c=0
 for i,v in enumerate(y):
  rx=i+1;ry=v+1;q=1+sum(w<v for w in y[:i]);a+=(q-1)*(q-2);b+=(rx-1)*(rx-2)*(ry-1)*(ry-2);c+=(rx-2)*(ry-2)*(q-1)
 d=30*((n-2)*(n-3)*a+b-2*(n-2)*c)/(n*(n-1)*(n-2)*(n-3)*(n-4));z=math.pi**4*((n-1)*d/60+1/72)
 for boundary in [.3,.55,1.1,2.95,10.3]:
  key=(boundary,1 if z>=boundary else -1);h=nearest[key];heapq.heappush(h,(-abs(z-boundary),k,y.copy()))
  if len(h)>3:heapq.heappop(h)
for h in nearest.values():
 for _,_,y in h:cases.append((list(range(len(y))),y,[1]*len(y)))
for n in [5,6,12,20,100]:
 for kind in ['ordered','reverse','constant','both']:
  x=list(range(n));y=x.copy()
  if kind=='reverse':y=y[::-1]
  if kind in ['constant','both']:y=[1]*n
  if kind=='both':x=[1]*n
  cases.append((x,y,[1]*n))
s='options linesize=240 pagesize=10000; data d; input g n x y f; datalines;\n'
for g,(x,y,f) in enumerate(cases,1):
 for xx,yy,ff in zip(x,y,f):s+=f'{g} {sum(f)} {xx} {yy} {ff}\n'
s+=';\nods exclude all; ods output HoeffdingCorr=h;\nproc corr data=d hoeffding; by g n; var x; with y; freq f; run;\nods exclude none;data _null_;set h;file print;put "ROW " g best12. n best12. x e25.17 Px e25.17;run;\n'
Path('/private/tmp/dev5-hoeffding-heldout.sas').write_text(s)
print(len(cases))
