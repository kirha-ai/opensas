from pathlib import Path
import math
import numpy as np
here = Path(__file__).resolve().parent
rows = []
for line in (here / 'dense.txt').read_text().splitlines():
    if not line.startswith('ROW'): continue
    n, d, p = map(float, (line[16:28], line[28:53], line[53:78]))
    z = math.pi**4 * ((n - 1) * d / 60 + 1 / 72)
    if 1e-5 < p < 1: rows.append((z, p))
rows = np.array(sorted(set(rows)))
pieces=[]
for lo,hi,trans,deg in [(.38,.55,'cdf',4),(.55,1.1,'p',7),(1.1,2.95,'p',8),(2.95,10.3,'logp',8)]:
 a=rows[(rows[:,0]>lo)&(rows[:,0]<hi)];x=a[:,0];v=a[:,1]
 fn={'cdf':lambda p:np.log1p(-p),'p':lambda p:p,'logp':np.log}[trans]
 previous=np.polynomial.Chebyshev.fit(x,fn(v),deg-1,domain=[lo,hi])
 fit=np.polynomial.Chebyshev.fit(x,fn(v),deg,domain=[lo,hi]);pieces.append((lo,hi,trans,fit))
 print('Degree evidence:',trans,'unique discovery',len(x),'degree',deg-1,'residual',max(abs(previous(x)-fn(v))),'degree',deg,'residual',max(abs(fit(x)-fn(v))))
 print(lo,hi,repr(fit.coef.tolist()))
def predict(n,d):
 if n<=5:return None
 if d>=1:return 0.
 z=math.pi**4*((n-1)*d/60+1/72)
 branch_z=z-(math.pi**4/72-1.3529)
 if branch_z<.3:return 1.
 if branch_z>10.3:return .00001
 for lo,hi,trans,fit in pieces:
  if branch_z<=hi:
   v=fit(z);return 1-math.exp(v) if trans=='cdf' else math.exp(v) if trans=='logp' else v
for name, expected_count in [('dense.txt',2500), ('boundaries.txt',10), ('switch.txt',365), ('heldout.txt',500), ('final-boundaries.txt',10)]:
 errors=[]; missing=0; count=0
 for l in (here / name).read_text().splitlines():
  if not l.startswith('ROW'):continue
  n,d=map(float,[l[16:28],l[28:53]]);ps=l[53:78].strip();p=None if ps=='.' else float(ps);pred=predict(n,d)
  count+=1
  if p is None or pred is None:
   assert p==pred, ('missing mismatch',l)
   missing+=1
  else:errors.append(abs(p-pred))
 assert count==expected_count, (name,count)
 assert max(errors)<5e-13, (name,max(errors))
 print(name, 'cases',count,'missing',missing,'max absolute error',max(errors))
