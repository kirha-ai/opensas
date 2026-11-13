"""Bounded, prespecified grids testing initialization versus unit effects."""
from pathlib import Path
import json
root=Path(__file__).parent
cases=[]
scales=[.02,.05,.1,.2,.3,.4,.5,.7,1,2,4,6,7,8,8.2,8.4,8.6,8.7,8.71,8.712,8.713,8.72,8.75,8.8,9,10,12]
for scale in scales:
    cases.append(dict(group='discovery',n=41,a=.5,b=1,family='power',scale=scale,fitbeta=None,alpha=None))
# Test the discovery predictor .002/min(x) on different sample sizes/shapes.
# It is a candidate to falsify, never used to produce expected fit parameters.
for n,a in [(23,.5),(67,.8)]:
    crossing=.002/((.625/(n+.25))**(1/a))
    for multiplier in [.5,.9,.99,.999,1.001,1.01,1.1,2]:
        cases.append(dict(group='power-heldout',n=n,a=a,b=1,family='power',scale=crossing*multiplier,fitbeta=None,alpha=None))
# Fresh non-beta1 beta shapes and sample sizes; both fixed beta<1 and >1
# distinguish a support-box hypothesis from a zero shape-gradient special case.
for n,a,b,fitbeta in [(31,2,3,1.5),(53,.7,2,.7)]:
    for scale in [.01,.1,1,10,100]:
        cases.append(dict(group='beta-heldout',n=n,a=a,b=b,family='beta',scale=scale,fitbeta=fitbeta,alpha=None))
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
    c['id']=f'grid_{k:03d}'
    quantile=f'((i-.375)/({c["n"]}+.25))**(1/{c["a"]})' if c['b']==1 else f'quantile("beta",(i-.375)/({c["n"]}+.25),{c["a"]},{c["b"]})'
    s+=f'%let case={c["id"]}; data d; do i=1 to {c["n"]}; x={c["scale"]:.17g}*({quantile}); output; end; run;\n'
    s+="%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;\n"
    opts='theta=0 sigma=est'+(f' beta={c["fitbeta"]}' if c['fitbeta'] is not None else '')
    s+=f'%let case={c["id"]}; title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / {c["family"]}({opts}) noplot; run; %show;\n'
(root/'scale-grid.sas').write_text(s)
(root/'scale-grid-inputs.json').write_text(json.dumps(cases,indent=2)+'\n')
print('Prespecified cases:',len(cases))
