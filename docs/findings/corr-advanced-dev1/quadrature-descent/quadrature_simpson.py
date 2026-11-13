import math
from statistics import NormalDist
phi=lambda x:math.exp(-x*x/2)/math.sqrt(2*math.pi)
Phi=lambda x:math.erfc(-x/math.sqrt(2))/2
def interval(lo,hi):
 return (math.erfc(lo/math.sqrt(2))-math.erfc(hi/math.sqrt(2)))/2 if lo>0 else (math.erfc(-hi/math.sqrt(2))-math.erfc(-lo/math.sqrt(2)))/2

def integral(f,a,b):
 c=(a+b)/2; fa,fb,fc=f(a),f(b),f(c); whole=(b-a)*(fa+4*fc+fb)/6
 def recurse(a,b,fa,fb,fc,old,tol,depth):
  c=(a+b)/2; fl=f((a+c)/2);fr=f((c+b)/2)
  left=(c-a)*(fa+4*fl+fc)/6;right=(b-c)*(fc+4*fr+fb)/6
  if depth==0 or abs(left+right-old)<=15*tol:return left+right+(left+right-old)/15
  return recurse(a,c,fa,fc,fl,left,tol/2,depth-1)+recurse(c,b,fc,fb,fr,right,tol/2,depth-1)
 return recurse(a,b,fa,fb,fc,whole,max(abs(whole)*1e-10,1e-300),18)

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
