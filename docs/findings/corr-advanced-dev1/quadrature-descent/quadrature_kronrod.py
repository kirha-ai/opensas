import math
from statistics import NormalDist
phi=lambda x:math.exp(-x*x/2)/math.sqrt(2*math.pi)
Phi=lambda x:math.erfc(-x/math.sqrt(2))/2
def interval(lo,hi):
 return (math.erfc(lo/math.sqrt(2))-math.erfc(hi/math.sqrt(2)))/2 if lo>0 else (math.erfc(-hi/math.sqrt(2))-math.erfc(-lo/math.sqrt(2)))/2

# Standard Gauss 7 / Kronrod 15 mathematical rule; numerical weights from QUADPACK.
_XK=(.9914553711208126392068547,.9491079123427585245261897,.8648644233597690727897128,.7415311855993944398638648,.5860872354676911302941448,.4058451513773971669066064,.2077849550078984676006894)
_WK=(.02293532201052922496373201,.06309209262997855329070066,.1047900103222501838398763,.1406532597155259187451896,.1690047266392679028265834,.1903505780647854099132564,.2044329400752988924141620,.2094821410847278280129992)
_WG=(.1294849661688696932706114,.2797053914892766679014678,.3818300505051189449503698,.4179591836734693877551020)
def _panel(f,a,b):
 middle=(a+b)/2;half=(b-a)/2;fc=f(middle)
 kronrod=_WK[7]*fc;gauss=_WG[3]*fc;absolute=_WK[7]*abs(fc);samples=[]
 for i,x in enumerate(_XK):
  low=f(middle-half*x);high=f(middle+half*x);samples.append((low,high))
  kronrod+=_WK[i]*(low+high);absolute+=_WK[i]*(abs(low)+abs(high))
  if i%2:gauss+=_WG[i//2]*(low+high)
 mean=kronrod/2;variation=_WK[7]*abs(fc-mean)
 for w,(low,high) in zip(_WK,samples):variation+=w*(abs(low-mean)+abs(high-mean))
 variation*=abs(half);absolute*=abs(half);error=abs((kronrod-gauss)*half)
 if variation and error:error=variation*min(1.,(200*error/variation)**1.5)
 error=max(error,50*2.220446049250313e-16*absolute)
 return kronrod*half,error

def integral(f,a,b):
 value,error=_panel(f,a,b);panels=[(a,b,value,error)]
 for _ in range(4096):
  total=math.fsum(p[2] for p in panels);error=math.fsum(p[3] for p in panels)
  if error<=max(abs(total)*1e-10,1e-300):return total
  index=max(range(len(panels)),key=lambda i:panels[i][3]);a,b,_,_=panels.pop(index)
  m=(a+b)/2
  if m==a or m==b:raise ArithmeticError('quadrature roundoff limit')
  left,le=_panel(f,a,m);right,re=_panel(f,m,b)
  panels.extend([(a,m,left,le),(m,b,right,re)])
 raise ArithmeticError('quadrature subdivision limit')

def rectangle(xl,xu,yl,yu,rho):
 sd=math.sqrt((1-rho)*(1+rho)); cuts=[xl,xu]
 for point in [0,-8,-4,-2,2,4,8]+[(v+k*sd)/rho for v in (yl,yu) for k in (-12,-8,-4,0,4,8,12)] if rho else [0]:
  if xl<point<xu:cuts.append(point)
 cuts=sorted(set(cuts));f=lambda x:phi(x)*interval((yl-rho*x)/sd,(yu-rho*x)/sd)
 return sum(integral(f,a,b) for a,b in zip(cuts,cuts[1:]))
def cell(par,i,j):
 tx=[-40,*par[:2],40];ty=[-40,*par[2:4],40]; return rectangle(tx[i],tx[i+1],ty[j],ty[j+1],par[-1])
def pdf2(x,y,r):
 if abs(x)>39 or abs(y)>39:return 0
 v=(1-r)*(1+r);return math.exp(-((x-r*y)**2/v+y*y)/2)/(2*math.pi*math.sqrt(v))
def derivative(par,i,j):
 tx=[-40,*par[:2],40];ty=[-40,*par[2:4],40];r=par[-1];sd=math.sqrt(1-r*r);xl,xu=tx[i:i+2];yl,yu=ty[j:j+2];out=[0.]*5
 if i>0:out[i-1]=-phi(xl)*interval((yl-r*xl)/sd,(yu-r*xl)/sd)
 if i<2:out[i]=phi(xu)*interval((yl-r*xu)/sd,(yu-r*xu)/sd)
 if j>0:out[2+j-1]=-phi(yl)*interval((xl-r*yl)/sd,(xu-r*yl)/sd)
 if j<2:out[2+j]=phi(yu)*interval((xl-r*yu)/sd,(xu-r*yu)/sd)
 out[-1]=pdf2(xu,yu,r)-pdf2(xl,yu,r)-pdf2(xu,yl,r)+pdf2(xl,yl,r)
 return out
def solve(m,b):
 m=[list(row)+[v] for row,v in zip(m,b)];n=len(b)
 for i in range(n):
  pivot=max(range(i,n),key=lambda j:abs(m[j][i]));m[i],m[pivot]=m[pivot],m[i];v=m[i][i];m[i]=[x/v for x in m[i]]
  for j in range(n):
   if i==j:continue
   v=m[j][i];m[j]=[x-v*y for x,y in zip(m[j],m[i])]
 return [row[-1] for row in m]
def info(par,counts):
 n=sum(counts);m=[[0.]*5 for _ in range(5)]
 for k in range(9):
  p=cell(par,k//3,k%3);g=derivative(par,k//3,k%3)
  if p==0:continue
  for i in range(5):
   for j in range(5):m[i][j]+=n*g[i]*g[j]/p
 return m
def gradient(par,counts):
 g=[0.]*5
 for k,n in enumerate(counts):
  if n==0:continue
  p=cell(par,k//3,k%3);d=derivative(par,k//3,k%3)
  for i in range(5):g[i]-=n*d[i]/p
 return g
def observed(par,counts):
 m=[[0.]*5 for _ in range(5)]
 for j in range(5):
  h=1e-5 if j<4 else (1-abs(par[-1]))*1e-3
  plus=par.copy();minus=par.copy();plus[j]+=h;minus[j]-=h
  gp=gradient(plus,counts);gm=gradient(minus,counts)
  for i in range(5):m[i][j]=(gp[i]-gm[i])/(2*h)
 return m
if __name__=='__main__':
 counts=[10,4,0,0,8,2,0,0,7]
 params=[NormalDist().inv_cdf(p/31) for p in [14,24,10,22]]+[0.9990304484694]
 for rho in [.99729481288087,.9990304484694,.9992481361016745]:
  params[-1]=rho
  print('rho',rho,'expectedSE',math.sqrt(solve(info(params,counts),[0,0,0,0,1])[-1]),'observedSE',math.sqrt(solve(observed(params,counts),[0,0,0,0,1])[-1]),flush=True)
