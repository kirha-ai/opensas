"""Separate conditional shape fits for retained joint successes and failures."""
from pathlib import Path
import json
root=Path(__file__).parent
source=json.loads((root/'fallback-mixtures-inputs.json').read_text());cases=[]
s='''options nonumber nodate;
%macro show;
%put DEV3_CASE &case;
%if %sysfunc(exist(p)) %then %do;
data _null_; set p; put 'DEV3_PARAMETER ' Symbol $ ' ' Estimate hex16.; run;
proc datasets lib=work nolist; delete p; quit;
%end;
%mend;
'''
for index in [0,4,7,12,29,31]:
    c=source[index];x=c['values'];sigma=max(x)-min(x)+.002
    cases.append(dict(id=c['id'],values=x,theta=c['theta'],sigma=sigma))
    s+=f'%let case={c["id"]}; data d; input x @@; datalines;\n'+' '.join(format(v,'.17g') for v in x)+'\n;\n'
    s+=f'title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta={c["theta"]:.17g} sigma={sigma:.17g} alpha=est) noplot; run; %show;\n'
(root/'power-conditional-controls.sas').write_text(s)
(root/'power-conditional-controls-inputs.json').write_text(json.dumps(cases,indent=2)+'\n')
