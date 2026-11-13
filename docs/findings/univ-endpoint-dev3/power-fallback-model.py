"""Hypothesis models only: width validity and conditional shape starts are separate."""
import math

def model(x,theta,fixed_alpha=None):
    n=len(x);span=max(x)-min(x)
    if n<4 or span<=0:return {'width_available':False}
    mean=math.fsum(x)/n
    variance=math.fsum((v-mean)**2 for v in x)/(n-1)
    skew=n*math.fsum((v-mean)**3 for v in x)/((n-1)*(n-2)*variance**1.5)
    kurt=n*(n+1)*math.fsum((v-mean)**4 for v in x)/((n-1)*(n-2)*(n-3)*variance**2)-3*(n-1)**2/((n-2)*(n-3))
    denominator=1.5*skew*skew-kurt
    total=(6+3*kurt-3*skew*skew)/denominator if denominator else float('nan')
    valid=denominator>0 and total>0 and math.isfinite(total)
    sigma=span+.002
    if valid:
        r2=skew*skew*(total+2)**2/(16*(total+1)+skew*skew*(total+2)**2)
        valid=0<=r2<1
        if valid:
            width=2*math.sqrt(variance*(total+1)/(1-r2))
            sigma=span+min(.002,.1*(width-span))
    result={'width_available':True,'four_moment_valid':valid,'sigma':sigma,'feasible':theta<min(x) and sigma>max(x)-theta}
    if not result['feasible']:return result
    ym=(mean-theta)/sigma;yv=variance/(sigma*sigma)
    start=ym*(ym*(1-ym)/yv-1)
    target=-n/math.fsum(math.log((v-theta)/sigma) for v in x)
    result.update(two_moment_alpha=start,conditional_alpha=target,
                  positive_start=start>0,
                  two_moment_newton=start>0 and start<2*target,
                  default_one_newton=target>.5,
                  capped_start_newton=start>0 and min(start,1)<2*target)
    if fixed_alpha is not None:
        result.update(positive_start=True,two_moment_newton=True,default_one_newton=True,capped_start_newton=True)
    return result

if __name__=='__main__':
    from pathlib import Path
    import json
    root=Path(__file__).parent
    fixture=root.parents[2]/'src/stat/testdata/univ_endpoint_power_dev3_cases.txt'
    rows=[]
    for line in fixture.read_text().splitlines():
        if line.startswith('#'):continue
        name,theta,alpha,sigma,expected_a,values=line.split('|')
        prediction=model(list(map(float,values.split(','))),float(theta),None if alpha=='est' else float(alpha))
        row=dict(id=name,oracle_curve=sigma!='est',model=prediction)
        if sigma!='est':
            row['oracle_sigma']=float(sigma);row['oracle_alpha']=float(expected_a)
            row['sigma_residual']=prediction['sigma']-float(sigma)
            row['alpha_residual']=(prediction['conditional_alpha'] if alpha=='est' else float(alpha))-float(expected_a)
        rows.append(row)
    assert len(rows)==85
    for policy in ['positive_start','two_moment_newton','default_one_newton','capped_start_newton']:
        errors=[r['id'] for r in rows if (r['model'].get('feasible',False) and r['model'].get(policy,False))!=r['oracle_curve']]
        print(policy,len(errors),errors)
    (root/'existing85-shape-start-audit.json').write_text(json.dumps(rows,indent=2,allow_nan=False)+'\n')

    print('Existing85 max sigma residual',max(abs(r['sigma_residual']) for r in rows if r['oracle_curve']))
    print('Existing85 max alpha residual',max(abs(r['alpha_residual']) for r in rows if r['oracle_curve']))
