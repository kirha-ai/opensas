"""Bounded discriminator: conditional blocks versus joint shape/scale fitting."""
from pathlib import Path
import json
root=Path(__file__).parent
cases=[]
for scale in [.01,.1,1]:
    cases.append(dict(scale=scale,alpha=None,sigma_factor=None,kind='joint'))
    for alpha in [.75,1,1.5,2,3]:cases.append(dict(scale=scale,alpha=alpha,sigma_factor=None,kind='scale-only'))
    for factor in [1.001,1.02,1.1]:cases.append(dict(scale=scale,alpha=None,sigma_factor=factor,kind='shape-only'))
s='''options nonumber nodate;
%macro show;
%put DEV3_CASE &case;
%if %sysfunc(exist(p)) %then %do;
data _null_; set p; put 'DEV3_PARAMETER ' Symbol $ ' ' Estimate hex16.; run;
proc datasets lib=work nolist; delete p; quit;
%end;
%mend;
'''
for i,c in enumerate(cases):
    c['id']=f'coupling_{i:03d}'
    s+=f'%let case={c["id"]}; data d; do i=1 to 31; x={c["scale"]:.17g}*quantile("beta",(i-.375)/31.25,2,3); output; end; run;\n'
    s+="%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;\n"
    if c['sigma_factor'] is not None:
        s+=f'proc means data=d noprint; var x; output out=m max=maximum; run; data _null_; set m; call symputx("sig",put(maximum*{c["sigma_factor"]},best32.)); run;\n'
    opts='theta=0 beta=1.5 alpha='+('est' if c['alpha'] is None else str(c['alpha']))+' sigma='+('est' if c['sigma_factor'] is None else '&sig')
    s+=f'title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / beta({opts}) noplot; run; %show;\n'
(root/'beta-coupling.sas').write_text(s)
(root/'beta-coupling-inputs.json').write_text(json.dumps(cases,indent=2)+'\n')
print('Conditional/joint cases',len(cases))
