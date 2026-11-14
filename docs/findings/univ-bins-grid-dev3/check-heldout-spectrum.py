from pathlib import Path
from read_probe import read
import math
root=Path(__file__).parent
samples,_=read(root/'exact-reflection-window.log');x=[r['x'] for r in samples['exact']]
expected,_=read(root/'heldout-schema.log');step=(x[-1]-x[0])/128;iqr=x[12]-x[4]
for name,kind,c in [('held2','q',1),('held3','t',2)]:
 h=c*iqr*len(x)**(-.2)
 for N in [256,512]:
  origin=x[0]-(N-128)/2*step;mass=[0.]*N
  for v in x:
   pos=(v-origin)/step;j=math.floor(pos);w=pos-j;mass[j]+=1-w;mass[j+1]+=w
  phi=[]
  for k in range(N//2+1):
   t=2*math.pi*k*h/(N*step)
   phi.append(1 if k==0 else 3*(math.sin(t)-t*math.cos(t))/t**3 if kind=='q' else (math.sin(t/2)/(t/2))**2)
  response=[(phi[0]+phi[-1]*(-1)**j+2*sum(phi[k]*math.cos(2*math.pi*k*j/N) for k in range(1,N//2)))/(N*step) for j in range(N)]
  for rule in ['ceil','floor','positive','exact','none']:
   raw=[]
   for i in range(N):
    sumv=sum(w*response[(i-j)%N] for j,w in enumerate(mass))/len(x)
    if rule=='none':keep=True
    elif rule=='exact':keep=any(w>0 and abs(i-j)*step<=h for j,w in enumerate(mass))
    else:keep=any(w>0 and abs(i-j)<=(math.floor(h/step) if rule=='floor' else math.ceil(h/step)) and (rule!='positive' or response[(i-j)%N]>0) for j,w in enumerate(mass))
    raw.append(max(0,sumv) if keep else 0)
   errors=[]
   for r in expected[name]:
    q=(r['_VALUE_']-origin)/step;j=math.floor(q);w=q-j
    got=(1-w)*raw[j]+w*raw[min(j+1,N-1)]
    errors.append((abs(got-r['_DENSITY_']),r['_VALUE_'],got,r['_DENSITY_']))
   print(name,N,rule,max(errors),'positive',max(e for e in errors if e[3]>0))
