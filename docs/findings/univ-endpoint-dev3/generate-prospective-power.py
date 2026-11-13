"""Freeze prospective power validation, free-location probes and repair controls."""
from pathlib import Path
import json
root=Path(__file__).parent
cases=[]
designs=[(29,.6,1.4,-4,.1),(59,.35,1,7,2),(83,1.4,1,0,.01),(19,2,5,0,.1)]
for n,a,b,offset,scale in designs:
    for alpha in [None,.4,2]:
        cases.append(dict(group='fixed-theta',n=n,a=a,b=b,offset=offset,scale=scale,theta=offset,sigma=None,alpha=alpha))
for values in [[1,10,10,10,10,10,19],[1,2,3],[1,2,3,4],[1,1,1,1],[1,1,1,1,20]]:
    for alpha in [None,.5]:
        cases.append(dict(group='moment-edge',values=values,theta=min(values)-.0001,sigma=None,alpha=alpha))
for n,a,b in [(29,.6,1.4),(59,.35,1)]:
    for offset,scale in [(-4,.1),(0,1),(5,10)]:
        for mode in ['location','joint']:
            cases.append(dict(group=mode,n=n,a=a,b=b,offset=offset,scale=scale,theta=None,sigma=scale if mode=='location' else None,alpha=a if mode=='location' else None))
s='''options nonumber nodate;
%macro show;
%put DEV3_CASE &case;
%if %sysfunc(exist(p)) %then %do;
data _null_; set p; put 'DEV3_PARAMETER ' Symbol $ ' ' Estimate hex16.; run;
proc datasets lib=work nolist; delete p; quit;
%end;
%mend;
'''
for k,c in enumerate(cases):
    c['id']=f'prospective_{k:03d}'
    s+=f'%let case={c["id"]};\n'
    if 'values' in c:
        s+='data d; input x @@; datalines;\n'+' '.join(map(str,c['values']))+'\n;\n'
    else:
        q=f'(i-.375)/({c["n"]}+.25)'
        quant=f'({q})**(1/{c["a"]})' if c['b']==1 else f'quantile("beta",{q},{c["a"]},{c["b"]})'
        s+=f'data d; do i=1 to {c["n"]}; x={c["offset"]}+{c["scale"]:.17g}*({quant}); output; end; run;\n'
    s+="%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;\n"
    opts=' '.join(k+'='+('est' if c[k] is None else str(c[k])) for k in ['theta','sigma','alpha'])
    s+=f'title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power({opts}) noplot; run; %show;\n'
(root/'prospective-power.sas').write_text(s)
(root/'prospective-power-inputs.json').write_text(json.dumps(cases,indent=2)+'\n')
print('Frozen prospective cases:',len(cases))
