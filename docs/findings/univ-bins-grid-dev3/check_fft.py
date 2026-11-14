from read_probe import read
from pathlib import Path
import math
x=[1,2,3,4,6,8,10,15];origin=min(x);step=(max(x)-origin)/128
mass=[0.]*129
for v in x:
 p=(v-origin)/step;i=math.floor(p);w=p-i
 mass[i]+=(1-w)/len(x)
 if w:mass[i+1]+=w/len(x)

def evaluate(c,kind='Normal',lower=None,upper=None):
 h=c*6.5*len(x)**(-.2);pad=(3 if kind=='Normal' else 1)*h
 N=256 if pad<=(max(x)-origin)/2 else 512
 lo=-(N-128)//2;hi=lo+N-1
 def K(z):
  return math.exp(-z*z/2)/math.sqrt(2*math.pi) if kind=='Normal' else (.75*(1-z*z) if abs(z)<=1 else 0) if kind=='Quadratic' else max(0,1-abs(z))
 spectrum=[]
 for k in range(N//2+1):
  t=2*math.pi*k*h/(N*step)
  phi=1 if k==0 else math.exp(-t*t/2) if kind=='Normal' else 3*(math.sin(t)-t*math.cos(t))/(t*t*t) if kind=='Quadratic' else (math.sin(t/2)/(t/2))**2
  spectrum.append(phi)
 kval=[]
 for j in range(N):
  total=spectrum[0]+spectrum[-1]*math.cos(math.pi*j)
  total+=2*sum(spectrum[k]*math.cos(2*math.pi*k*j/N) for k in range(1,N//2))
  kval.append(total/(N*step))
 raw=[]
 for i in range(lo,hi+1):
  value=max(0,sum(w*kval[(i-j)%N] for j,w in enumerate(mass)))
  if kind!='Normal' and not any(w>0 and abs(i-j)<=math.ceil(h/step) for j,w in enumerate(mass)):value=0
  raw.append(value)
 def at(p):
  q=(p-origin)/step;i=math.floor(q);f=q-i
  # interpolate valid FFT nodes, zero beyond them
  a=raw[i-lo] if lo<=i<=hi else 0
  b=raw[i+1-lo] if lo<=i+1<=hi else 0
  return (1-f)*a+f*b
 def bounded(i):
  p=origin+i*step
  if lower is not None and p<lower:return 0
  if upper is not None and p>upper:return 0
  return at(p)+(at(2*lower-p) if lower is not None and math.floor(-pad/step)<=math.floor((2*lower-p-origin)/step)<=128+math.ceil(pad/step) else 0)+(at(2*upper-p) if upper is not None and math.floor(-pad/step)<=math.floor((2*upper-p-origin)/step)<=128+math.ceil(pad/step) else 0)
 def density(p):
  q=(p-origin)/step;i=math.floor(q);f=q-i
  return (1-f)*bounded(i)+f*bounded(i+1)
 return density,N
r,_=read(Path(__file__).parent/'constants-grid.log')
for name,c,kind,lower,upper in [('kgrid0',.5,'Normal',None,None),('kgrid1',1,'Normal',None,None),('kgrid2',2,'Normal',None,None),('kgrid3',.5,'Normal',None,None),('kgrid4',.5,'Normal',0,20),('kgrid5',.5,'Quadratic',None,None),('kgrid6',.5,'Triangular',None,None)]:
 fn,N=evaluate(c,kind,lower,upper);err=[(abs(fn(v['_VALUE_'])-v['_DENSITY_']),v['_VALUE_'],fn(v['_VALUE_']),v['_DENSITY_']) for v in r[name]]
 print(name,N,max(err))
