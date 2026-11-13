import math
M=300
terms=[(1/(k*k),sum(k%d==0 for d in range(1,k+1))) for k in range(1,M+1)]
mean=math.pi**4/72-sum(v*c/2 for v,c in terms)
xs=[((n-1)*math.pi**4/60*d+math.pi**4/72) for n,d in [(8,1/56),(8,9/28),(12,5/198),(20,1),(12,1)]]
sums=[0.0]*len(xs)
h=.02
for j in range(15001):
 t=j*h
 phase=mean*t; mag=0
 for v,c in terms:
  phase+=.5*c*math.atan(t*v); mag-=.25*c*math.log1p(t*t*v*v)
 weight=1 if j in (0,15000) else 4 if j%2 else 2
 for i,x in enumerate(xs):
  value=(math.pi**4/72-x) if j==0 else math.sin(phase-x*t)*math.exp(mag)/t
  sums[i]+=weight*value
print(xs,[.5+s*h/3/math.pi for s in sums])
