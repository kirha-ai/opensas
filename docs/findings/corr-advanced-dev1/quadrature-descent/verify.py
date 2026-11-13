"""Reproduce the bounded case-2 audit and retain every old solver case."""
from pathlib import Path
import math, runpy
ROOT=Path(__file__).resolve().parent
cases=__import__('json').loads((ROOT/'cases.json').read_text())
expected={}
for line in (ROOT/'oracle.txt').read_text().splitlines():
    fields=line.split()
    if len(fields)==6 and fields[0].isdigit():
        expected[int(fields[0])]=[None if x=='.' else float(x) for x in fields[1:]]
assert len(cases)==len(expected)==40

def audit(quadrature, relative=False):
    model=runpy.run_path(str(ROOT/'candidate.py'))
    model['analyze'].__globals__['base']=runpy.run_path(str(ROOT/quadrature))
    model['analyze'].__globals__['RELATIVE_STOP']=relative
    model['cdf'].cache_clear()
    failures=[]
    for case in cases:
        result=model['analyze'](case);reference=expected[case['g']]
        if 'failure' in result:
            failures.append(case['g']);continue
        n,r,se,_,lr=reference
        if (result['n']!=n or abs(result['rho']-r)>(5e-6 if se==0 else 5e-8)
            or not math.isclose(result['se'],se,rel_tol=1e-4,abs_tol=5e-6)
            or abs(result['lr']-lr)>1e-7+2e-9*n):
            failures.append(case['g'])
    return failures
before=audit('quadrature_simpson.py');after=audit('quadrature_kronrod.py')
assert before==[2,3,17,21,22],before
assert after==[3,21,22],after
assert set(after).issubset(before)
assert audit('quadrature_kronrod.py', relative=True)==after
print('Baseline: 35/40. Corrected quadrature: 37/40; all former passes retained.')
print('Remaining failures: 3, 21, 22. This is not full solver acceptance.')

states=[[-.4956306291470207,.8088444041132948,.2855878655411077,.9947335197981],
        [-.495630632452179,.8088444028834387,.2855878638305473,.9950991078001906]]
quad=runpy.run_path(str(ROOT/'quadrature_kronrod.py'));scores=[]
for state in states:
    xs=[-40,*state[:2],40];ys=[-40,state[2],40];values=[]
    for i in range(3):
        for j in range(2):
            p=quad['rectangle'](xs[i],xs[i+1],ys[j],ys[j+1],state[3])
            transposed=quad['rectangle'](ys[j],ys[j+1],xs[i],xs[i+1],state[3])
            assert abs(p-transposed)<3e-13
            values.append(p)
    assert abs(sum(values)-1)<3e-13
    scores.append(-sum(n*math.log(p) for n,p in zip([280,0,273,161,0,189],values) if n))
assert abs(scores[0]-1227.6442891538863)<5e-9
assert abs(scores[1]-1227.6442884965318)<5e-9
assert scores[1]<scores[0]-5e-7
print('Partition mass, transposition, and SAS likelihood-descent references: PASS.')
