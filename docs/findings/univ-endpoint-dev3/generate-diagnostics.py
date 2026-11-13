"""Independent synthetic M9 probes; no fitted constants enter the samples."""
from pathlib import Path
out = Path(__file__).parent
s = '''options nonumber nodate;
%macro show;
%put DEV3_CASE &case;
%if %sysfunc(exist(p)) %then %do;
data _null_; set p; put 'DEV3_PARAMETER ' Symbol $ ' ' Estimate hex16.; run;
proc print data=p noobs; format _numeric_ best32.; run;
proc datasets lib=work nolist; delete p; quit;
%end;
%mend;
'''
for key,shift,scale in [('base',0,1),('scaled',0,10),('small',0,.1),('translated',5,1)]:
    s += f'data p_{key}; do i=1 to 41; x={shift}+{scale}*((i-.375)/41.25)**2; output; end; run;\n'
    for limit in ([1,2,20,1000] if key=='base' else [20]):
        for endpoints in ['scale','both','theta']:
            opts={'scale':f'theta={shift} sigma=est','both':'theta=est sigma=est','theta':f'theta=est sigma={scale} alpha=.5'}[endpoints]
            case=f'power_{key}_{endpoints}_{limit}'
            s+=f'%let case={case}; title "&case"; ods output ParameterEstimates=p; proc univariate data=p_{key} noprint; histogram x / power({opts} maxiter={limit}) noplot; run; %show;\n'
for shift in [1,2,3]:
    for key,offset,scale in [('base',0,1),('scaled',0,10),('translated',5,1),('small',0,.1)]:
        s+=f'data g; do i=1 to 8; x={offset}+{scale}*(input(scan("1 2 3 4 6 8 10 15",i),best.)+{shift}); output; end; run;\n'
        case=f'pareto_shift{shift}_{key}'
        s+=f'%let case={case}; title "&case"; ods output ParameterEstimates=p; proc univariate data=g noprint; histogram x / pareto(theta={offset} edfnsamples=1) noplot; run; %show;\n'
(out/'solver-diagnostics.sas').write_text(s)
