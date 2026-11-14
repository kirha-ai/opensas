"""Verify the prospective native pivot discriminator and all retained cases."""
from pathlib import Path
import json,math,runpy
ROOT=Path(__file__).resolve().parent
# Full native expected-information matrix, printed by the actual SAS probe.
rows=[];collect=False
for line in (ROOT/'native-information.txt').read_text().splitlines():
 if line.strip().startswith('info'):collect=True;continue
 if collect and len(rows)<4:
  try:values=[float(v) for v in line.split()]
  except ValueError:continue
  if len(values)>=4:rows.append(values[:4])
assert len(rows)==4
for k in range(3):
 pivot=rows[k][k]
 for i in range(k+1,4):
  for j in range(k+1,4):rows[i][j]-=rows[i][k]*rows[k][j]/pivot
pivot=rows[3][3]
assert 11.5*pivot<1e-8<12*pivot
actual={}
for line in (ROOT/'transition-refined.txt').read_text().splitlines():
 fields=line.split()
 if len(fields)==5 and fields[0] in ('default','tiny','large'):
  actual[fields[0],int(fields[1])]=tuple(float(x) for x in fields[2:])
assert len(actual)==21
for group,scale in enumerate([8,10,11,12,13,20,11.5],1):
 for option in ('default','tiny','large'):
  n,r,se=actual[option,group]
  assert n==90*scale and se==0
  assert abs(r-(.98771303561774 if scale<12 else .999))<5e-8
  assert actual[option,group]==actual['default',group]
print('Native absolute-pivot transition and SINGULAR independence: PASS')

model=runpy.run_path(str(ROOT/'candidate.py'))
def read_rows(path):
 result={}
 for line in path.read_text().splitlines():
  fields=line.split()
  if len(fields)==6 and fields[0].isdigit():result[int(fields[0])]=[None if x=='.' else float(x) for x in fields[1:]]
 return result
def verify(cases,reference):
 errors=[]
 for case in cases:
  p=model['analyze'](case);n,r,se,_,lr=reference[case['g']]
  if 'failure' in p or r is None:errors.append(case['g']);continue
  se_ok=(p['se']==0)==(se==0)
  if se>0:se_ok=se_ok and abs(p['se']-se)<=5e-6 and abs(p['se']-se)<=1e-4*abs(se)
  if (p['n']!=n or abs(p['rho']-r)>(5e-6 if se==0 else 5e-8)
      or not se_ok or abs(p['lr']-lr)>1e-7+2e-9*n):errors.append(case['g'])
 return errors
old=ROOT.parent/'quadrature-descent'
assert verify(json.loads((old/'cases.json').read_text()),read_rows(old/'oracle.txt'))==[]
print('Existing cases: 40/40, including all former 37 passes')
failed=verify(json.loads((ROOT/'heldout.json').read_text()),read_rows(ROOT/'heldout.txt'))
assert failed==[1,8,17,18],failed
print('Independent holdout: 14/18; failures 1,8,17,18 retained. NOT full acceptance.')
