from pathlib import Path
import json
root=Path(__file__).parent
samples=[[1,1,1,1,1,1,1,20],[1,1,1,1,20,20,20,20],[1,5,5,5,5,5,5,5,9],[1,1.01,1.02,1.03,20],[1,1,1,2]]
cases=[]
s='''options nonumber nodate;
%macro show;
%put DEV3_CASE &case;
%if %sysfunc(exist(p)) %then %do;
data _null_; set p; put 'DEV3_PARAMETER ' Symbol $ ' ' Estimate hex16.; run;
proc datasets lib=work nolist; delete p; quit;
%end;
%mend;
'''
for k,values in enumerate(samples):
    for alpha in [None,.5]:
        name=f'initial_edge_{len(cases):02d}'
        cases.append(dict(id=name,group='initial-edge',values=values,theta=.9999,sigma=None,alpha=alpha))
        s+=f'%let case={name}; data d; input x @@; datalines;\n'+' '.join(map(str,values))+'\n;\n'
        s+="%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;\n"
        s+=f'title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=.9999 sigma=est alpha={"est" if alpha is None else alpha}) noplot; run; %show;\n'
(root/'initialization-edges.sas').write_text(s)
(root/'initialization-edges-inputs.json').write_text(json.dumps(cases,indent=2)+'\n')
