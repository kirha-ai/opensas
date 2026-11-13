"""Bounded solver discriminator; standard library only, no opensas imports.
Candidates and held-out set fixed before obtaining heldout.log.
Run: python3 discriminator.py [directory containing sweep/confirm/heldout logs]
"""
from pathlib import Path
from fractions import Fraction as F
import csv, math, sys
from decimal import Decimal, localcontext
BASE=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).resolve().parent
TRAIN=[(2,5,F('0.939')),(2,5,F('0.940'))]
HELD=[(n1,n2,F(a)) for n1,n2,alphas in [(3,4,['.939','.940','.941']), (5,2,['.949','.950','.951']), (2,7,['.937','.940','.943'])] for a in alphas]
MODELS=['analytic','golden_reset','newton_reset','newton_warm','golden_interior_reset']

def mass(n1,n2,r,q):
    return (1-float(r)*q)**n1*q**n2

def maximize(n1,n2,r,model,previous):
    r=float(r); upper=min(1.,1/r)
    if model=='analytic':
        q=min(upper,n2/(r*(n1+n2)))
    elif model.startswith('golden'):
        lo,hi=0.,upper; g=(math.sqrt(5)-1)/2
        x=hi-g*(hi-lo);y=lo+g*(hi-lo)
        for _ in range(64):
            if mass(n1,n2,r,x)<mass(n1,n2,r,y):lo=x;x=y;y=lo+g*(hi-lo)
            else:hi=y;y=x;x=hi-g*(hi-lo)
        q=(lo+hi)/2
        if model=='golden_reset':q=max([0.,q,upper],key=lambda t:mass(n1,n2,r,t))
    else:
        # Concave log likelihood; safeguarded Newton, constrained endpoints.
        lo,hi=0.,upper
        q=previous if model=='newton_warm' and previous is not None else upper/2
        q=max(upper*1e-12,min(upper*(1-1e-12),q))
        for _ in range(64):
            grad=n2/q-n1*r/(1-r*q)
            if grad>0:lo=q
            else:hi=q
            hess=-n2/q**2-n1*r*r/(1-r*q)**2
            trial=q-grad/hess
            if not lo<trial<hi:trial=(lo+hi)/2
            if trial==q:break
            q=trial
            if q==upper or r*q==1:break
        q=max([0.,q,upper],key=lambda t:mass(n1,n2,r,t))
    return mass(n1,n2,r,q),q

def exact_max(n1,n2,r):
    q=min(F(1),1/r,F(n2)/(r*(n1+n2)))
    return (1-r*q)**n1*q**n2

def path(n1,n2,alpha,model):
    point=F(1,2*n1+1);lo=point;hi=2*point;target=alpha/2
    rows=[];previous=None
    while True:
        value,previous=maximize(n1,n2,hi,model,previous)
        if value<=float(target):break
        hi=point+2*(hi-point)
    for step in range(1,101):
        mid=(lo+hi)/2
        value,previous=maximize(n1,n2,mid,model,previous)
        truth=exact_max(n1,n2,mid)
        stop=value<=float(target) and float(target)-value<=1e-6
        rows.append([n1,n2,str(alpha),model,step,str(mid),float(mid),str(truth),float(truth),previous,value,value-float(target),'stop' if stop else 'accept' if value>float(target) else 'reject'])
        if stop:return float(mid),rows
        if value>float(target):lo=mid
        else:hi=mid
    raise AssertionError('candidate exhausted')

def verify_score_tail(n1,n2,r):
    # Independent 70-digit quadratic constrained MLE for EACH candidate table.
    # Stationary equation: r*(n1+n2)*q^2-B*q+(x+y)=0,
    # B=r*(n1+y)+n2+x. Use the rationalized smaller root.
    with localcontext() as ctx:
        ctx.prec=70
        rd=Decimal(r.numerator)/Decimal(r.denominator)
        def z(x,y):
            if x+y==0:return Decimal(0)
            b=rd*(n1+y)+n2+x
            q=2*Decimal(x+y)/(b+(b*b-4*rd*(n1+n2)*(x+y)).sqrt())
            q=min(Decimal(1),1/rd,q)
            p=rd*q
            v=p*(1-p)/n1+rd*rd*q*(1-q)/n2
            delta=Decimal(x)/n1-rd*Decimal(y)/n2
            return delta/v.sqrt() if v else Decimal(0) if not delta else Decimal('Infinity').copy_sign(delta)
        observed=z(0,n2)
        selected=[(x,y) for x in range(n1+1) for y in range(n2+1) if z(x,y)<=observed]
        assert selected==[(0,n2)],(n1,n2,r,selected)

def read_log(name,prefix,count):
    text=(BASE/name).read_text()
    assert not any(line.startswith(('ERROR:','ERROR ','WARNING:')) for line in text.splitlines()),name
    rows=list(csv.reader(line for line in text.splitlines() if line.startswith(prefix+',')))
    assert len(rows)==count,(name,len(rows),count)
    return rows

def main():
    sweep=read_log('sweep.log','RESULT',768)
    confirm=read_log('confirm.log','CHECK',144)
    data={tuple(x[2:9])+(x[9].strip(),):float(x[10]) if x[10].strip()!='.' else math.inf for x in sweep}
    assert len(data)==768
    for k,v in data.items():
        if k[6]:assert v==data[k[:6]+('',)+k[7:]],('MAXTIME',k)
    for row in confirm:
        _,a,b,alpha,m,tr,col,name,v=row
        tc=str(3-int(col)) if tr in ['columns','both'] else col
        sw='1' if tr=='both' else '0'
        expected=data[(a,b,alpha,m,sw,tc,'',name.strip().replace('RRC'+col,'RRC'+tc))]
        actual=float(v) if v.strip()!='.' else math.inf
        assert actual==expected,row
    traces=[]; predictions={}
    for n1,n2,a in TRAIN+HELD:
        for model in MODELS:
            pred,rows=path(n1,n2,a,model);traces+=rows
            predictions[(n1,n2,a,model)]=pred
    score_checks={(row[0],row[1],F(row[5])) for row in traces}
    for n1,n2,r in score_checks:verify_score_tail(n1,n2,r)
    print(len(score_checks),'distinct shape/null SCORE tails independently enumerated at 70 decimal digits; all singleton.')
    with (BASE/'paths.csv').open('w') as f:
        w=csv.writer(f);w.writerow(['n1','n2','alpha','candidate','iteration','r_exact','r','p_exact','p','nuisance','candidate_p','p_minus_target','action']);w.writerows(traces)
    # Independent rational certificate: both alphas share the first five r's.
    p0=path(2,5,F('.939'),'analytic')[1];p1=path(2,5,F('.940'),'analytic')[1]
    assert [(r[5],r[-1]) for r in p0[:8]]==[(r[5],r[-1]) for r in p1[:8]]
    assert F(p0[4][5])==F(51,160)
    assert exact_max(2,5,F(51,160))==F(11881,25600)
    print('768 sweep + 144 confirmation endpoints checked; MAXTIME and physical swaps/repeats identical.')
    print('Training first five nulls: '+', '.join(r[5] for r in p0[:5]))
    print('At 51/160, exact max=11881/25600=.4641015625; residuals -.0053984375 and -.0058984375.')
    held=read_log('heldout.log','HOLD',18) if (BASE/'heldout.log').exists() else []
    results=[]
    for n1,n2,a in TRAIN+HELD:
        for method in ['noscore','score']:
            if (n1,n2,a) in TRAIN:oracle=data[(str(n1),str(n2),str(float(a)),method,'0','1','','XU_RRC1')]
            else:
                found=[float(x[5]) for x in held if (int(x[1]),int(x[2]),F(x[3]),x[4])==(n1,n2,a,method)]
                if not found:continue
                assert len(found)==1;oracle=found[0]
            verify_score_tail(n1,n2,F(str(oracle)))
            for model in MODELS:
                pred=predictions[(n1,n2,a,model)]
                results.append([n1,n2,str(a),method,model,oracle,pred,pred-oracle,abs(pred-oracle)<=5e-5,'train' if (n1,n2,a) in TRAIN else 'heldout'])
    with (BASE/'predictions.csv').open('w') as f:
        w=csv.writer(f);w.writerow(['n1','n2','alpha','method','candidate','sas','predicted','error','within_listing_precision','set']);w.writerows(results)
    for model in MODELS:
        for group in ['train','heldout']:
            rs=[r for r in results if r[4]==model and r[-1]==group]
            if rs:print(model,group,'matched',sum(r[8] for r in rs),'/',len(rs),'max error',max(abs(r[7]) for r in rs))
    print('No candidate parameters fitted to SAS endpoints.')

if __name__=='__main__':main()
