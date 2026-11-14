"""Frozen generic candidate for fresh SAS validation; no per-case fitted outputs."""
import runpy,math,json,hashlib
from pathlib import Path
from statistics import NormalDist
from functools import lru_cache
base=runpy.run_path(str(Path(__file__).resolve().parent.parent/'quadrature-descent/quadrature_kronrod.py'))
EPS=2.220446049250313e-16
RELATIVE_STOP=True
@lru_cache(maxsize=4096)
def cdf(x,y,r):
 if x<=-40 or y<=-40:return 0.
 if x>=40:return base['Phi'](y)
 if y>=40:return base['Phi'](x)
 if r>=0:
  if x<y:return base['Phi'](x)-base['rectangle'](-40,x,y,40,r)
  return base['Phi'](y)-base['rectangle'](x,40,-40,y,r)
 if x+y<=0:return base['rectangle'](-40,x,-40,y,r)
 return base['interval'](-y,x)+base['rectangle'](-40,-x,-40,-y,r)
def solve(matrix,rhs):
 n=len(rhs);m=[list(row)+[v] for row,v in zip(matrix,rhs)]
 for i in range(n):
  pivot=max(range(i,n),key=lambda j:abs(m[j][i]))
  if abs(m[pivot][i])<1e-8:
   for j in range(n):m[j][i]=0
   m[i]=[0.]*(n+1);m[i][i]=1;continue
  m[i],m[pivot]=m[pivot],m[i];v=m[i][i];m[i]=[x/v for x in m[i]]
  for j in range(n):
   if j==i:continue
   v=m[j][i];m[j]=[a-v*b for a,b in zip(m[j],m[i])]
 return [row[-1] for row in m]
def analyze(case):
 nr=len(case['x']);nc=len(case['y']);dim=nr+nc-1
 ix=sorted(range(nr),key=lambda i:case['x'][i]);iy=sorted(range(nc),key=lambda j:case['y'][j])
 xs=[case['x'][i] for i in ix];ys=[case['y'][j] for j in iy]
 counts=[case['scale']*case['counts'][i][j] for i in ix for j in iy];n=sum(counts)
 rows=[sum(counts[i*nc:(i+1)*nc]) for i in range(nr)];cols=[sum(counts[j::nc]) for j in range(nc)]
 p=[NormalDist().inv_cdf(sum(rows[:i])/n) for i in range(1,nr)]+[NormalDist().inv_cdf(sum(cols[:j])/n) for j in range(1,nc)]+[0.]
 def geometry(par,i,j):
  x=[-40,*par[:nr-1],40];y=[-40,*par[nr-1:-1],40];return x[i],x[i+1],y[j],y[j+1],par[-1]
 def cell(par,i,j):return base['rectangle'](*geometry(par,i,j))
 def represented(par,i,j):
  xl,xu,yl,yu,r=geometry(par,i,j);v=[cdf(xu,yu,r),cdf(xl,yu,r),cdf(xu,yl,r),cdf(xl,yl,r)]
  q=v[0]-v[1]-v[2]+v[3];return max(0.,q)
 def derivative(par,i,j):
  xl,xu,yl,yu,r=geometry(par,i,j);sd=math.sqrt((1-r)*(1+r));d=[0.]*dim;phi=base['phi'];interval=base['interval'];bpdf=base['pdf2']
  if i>0:d[i-1]=-phi(xl)*interval((yl-r*xl)/sd,(yu-r*xl)/sd)
  if i+1<nr:d[i]=phi(xu)*interval((yl-r*xu)/sd,(yu-r*xu)/sd)
  if j>0:d[nr+j-2]=-phi(yl)*interval((xl-r*yl)/sd,(xu-r*yl)/sd)
  if j+1<nc:d[nr+j-1]=phi(yu)*interval((xl-r*yu)/sd,(xu-r*yu)/sd)
  d[-1]=bpdf(xu,yu,r)-bpdf(xl,yu,r)-bpdf(xu,yl,r)+bpdf(xl,yl,r)
  return d
 def nll(par):
  if abs(par[-1])>=1 or any(par[i]<=par[i-1] for i in range(1,nr-1)) or any(par[i]<=par[i-1] for i in range(nr,dim-1)):return math.inf
  try:return -sum(v*math.log(cell(par,k//nc,k%nc)) for k,v in enumerate(counts) if v)
  except (ValueError,ZeroDivisionError):return math.inf
 null=nll(p);xs=[x-xs[0] for x in xs];ys=[y-ys[0] for y in ys]
 sx=sum(v*xs[k//nc] for k,v in enumerate(counts));sy=sum(v*ys[k%nc] for k,v in enumerate(counts));xx=sum(v*xs[k//nc]**2 for k,v in enumerate(counts));yy=sum(v*ys[k%nc]**2 for k,v in enumerate(counts));xy=sum(v*xs[k//nc]*ys[k%nc] for k,v in enumerate(counts))
 p[-1]=(xy-sx*sy/n)/math.sqrt((xx-sx*sx/n)*(yy-sy*sy/n))
 if abs(p[-1])>=1:return {'g':case['g'],'failure':'initial boundary'}
 tolerance=case.get('converge',1e-5)
 for iteration in range(1,201):
  info=[[0.]*dim for _ in range(dim)];g=[0.]*dim
  for cell_index,v in enumerate(counts):
   i,j=divmod(cell_index,nc);prob=cell(p,i,j);q=represented(p,i,j)
   if q<=0:
    if v:return {'g':case['g'],'failure':'occupied represented zero'}
    continue
   d=derivative(p,i,j);den=max(q,1e-12)
   for i in range(dim):
    if v:g[i]-=v*d[i]/prob
    for j in range(dim):info[i][j]+=n*d[i]*d[j]/den
  step=solve(info,g);rhs=[0.]*dim;rhs[-1]=1;variance=solve(info,rhs)[-1]
  old=nll(p);scale=1
  for backtrack in range(30):
   trial=[x-scale*d for x,d in zip(p,step)]
   if abs(trial[-1])>=1:trial[-1]=math.copysign(.999 if backtrack==0 else .9999,trial[-1])
   if (trial[-1]-p[-1])*step[-1]>=0 and abs(step[-1])>tolerance:scale/=2;continue
   if nll(trial)<=old+n*1e-10:break
   scale/=2
  else:return {'g':case['g'],'failure':'line search'}
  change=max(abs(a-b)/(1 if abs(a)<.01 else abs(a)) for a,b in zip(p,trial)) if RELATIVE_STOP else max(abs(a-b) for a,b in zip(p,trial));p=trial
  if change<tolerance:return {'g':case['g'],'n':n,'rho':p[-1],'se':math.sqrt(max(0,variance)),'lr':2*(null-nll(p)),'iterations':iteration}
 return {'g':case['g'],'failure':'iterations'}

