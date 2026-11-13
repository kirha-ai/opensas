"""Prospective tie/mixture tests, generated before inspecting any M9 results."""
from pathlib import Path
import json,importlib.util
root=Path(__file__).parent
spec=importlib.util.spec_from_file_location('model',root/'power-fallback-model.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
cases=[]
def add(group,values,gap,alpha=None):
    values=sorted(values)
    cases.append(dict(id=f'mixture_{len(cases):03d}',group=group,values=values,theta=min(values)-gap,alpha=alpha,prediction=m.model(values,min(values)-gap,alpha)))
for count in [3,5,7,11]:
    for gap in [1e-6,1e-4,1e-3]:add('symmetric-eight',[1]+[5]*count+[9],gap)
for count in [5,7]:
    for gap in [1e-4,3e-4,1e-3,1.5e-3]:add('symmetric-eighteen',[1]+[10]*count+[19],gap)
for low,high in [(2,1),(1,2),(2,2)]:
    for gap in [1e-4,1e-3]:add('asymmetric-ties',[1]*low+[5]*7+[9]*high,gap)
for gap in [1e-6,1e-4,1e-3]:add('jittered-center',[1,4.8,4.9,5,5,5,5.1,5.2,9],gap)
for scale,offset in [(10,-3),(.1,7)]:add('affine',[offset+scale*v for v in [1,5,5,5,5,5,5,5,9]],scale*.0001)
add('replicated',[1,5,5,5,5,5,5,5,9]*3,.0001)
for index in [0,3,12,16]:
    c=cases[index];add('fixed-alpha-control',c['values'],min(c['values'])-c['theta'],.5)
s='''options nonumber nodate;
%macro show;
%put DEV3_CASE &case;
%if %sysfunc(exist(p)) %then %do;
data _null_; set p; put 'DEV3_PARAMETER ' Symbol $ ' ' Estimate hex16.; run;
proc datasets lib=work nolist; delete p; quit;
%end;
%mend;
'''
for c in cases:
    s+=f'%let case={c["id"]}; data d; input x @@; datalines;\n'+' '.join(format(v,'.17g') for v in c['values'])+'\n;\n'
    s+="%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;\n"
    s+=f'title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta={c["theta"]:.17g} sigma=est alpha={"est" if c["alpha"] is None else c["alpha"]}) noplot; run; %show;\n'
(root/'fallback-mixtures.sas').write_text(s)
(root/'fallback-mixtures-inputs.json').write_text(json.dumps(cases,indent=2,allow_nan=False)+'\n')
print('Prospective cases',len(cases))
for name in ['positive_start','two_moment_newton','default_one_newton','capped_start_newton']:
 print(name, sum(c['prediction'].get('feasible',False) and c['prediction'].get(name,False) for c in cases),'predicted curves')
