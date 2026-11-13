"""One bounded follow-up: replicate likelihood and perturb the fixed beta shape."""
from pathlib import Path
import json
root=Path(__file__).parent
cases=[]
for copies in [3,10]:
    for scale in [.1,1,9]:
        cases.append(dict(group='replication',n=41,a=.5,b=1,family='power',scale=scale,fitbeta=None,copies=copies))
for fitbeta in [.9,.99,1.01,1.1,1.5]:
    for scale in [.1,1]:
        cases.append(dict(group='near-one',n=41,a=.5,b=1,family='beta',scale=scale,fitbeta=fitbeta,copies=1))
for n,a in [(23,.5),(67,.8)]:
    for scale in [.01,.1]:
        cases.append(dict(group='small-heldout',n=n,a=a,b=1,family='power',scale=scale,fitbeta=None,copies=1))
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
    c['id']=f'controlled_{k:03d}'
    s+=f'%let case={c["id"]}; data d; do i=1 to {c["n"]}; x={c["scale"]:.17g}*((i-.375)/({c["n"]}+.25))**(1/{c["a"]}); do copy=1 to {c["copies"]}; output; end; end; run;\n'
    s+="%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;\n"
    opts='theta=0 sigma=est'+(f' beta={c["fitbeta"]}' if c['fitbeta'] is not None else '')
    s+=f'title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / {c["family"]}({opts}) noplot; run; %show;\n'
(root/'controlled-grid.sas').write_text(s)
(root/'controlled-grid-inputs.json').write_text(json.dumps(cases,indent=2)+'\n')
print('Controlled cases:',len(cases))
