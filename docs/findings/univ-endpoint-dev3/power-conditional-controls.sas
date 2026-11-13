options nonumber nodate;
%macro show;
%put DEV3_CASE &case;
%if %sysfunc(exist(p)) %then %do;
data _null_; set p; put 'DEV3_PARAMETER ' Symbol $ ' ' Estimate hex16.; run;
proc datasets lib=work nolist; delete p; quit;
%end;
%mend;
%let case=mixture_000; data d; input x @@; datalines;
1 5 5 5 9
;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99999899999999997 sigma=8.0020000000000007 alpha=est) noplot; run; %show;
%let case=mixture_004; data d; input x @@; datalines;
1 5 5 5 5 5 9
;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99990000000000001 sigma=8.0020000000000007 alpha=est) noplot; run; %show;
%let case=mixture_007; data d; input x @@; datalines;
1 5 5 5 5 5 5 5 9
;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99990000000000001 sigma=8.0020000000000007 alpha=est) noplot; run; %show;
%let case=mixture_012; data d; input x @@; datalines;
1 10 10 10 10 10 19
;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99990000000000001 sigma=18.001999999999999 alpha=est) noplot; run; %show;
%let case=mixture_029; data d; input x @@; datalines;
7 47 47 47 47 47 47 47 87
;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=6.9989999999999997 sigma=80.001999999999995 alpha=est) noplot; run; %show;
%let case=mixture_031; data d; input x @@; datalines;
1 1 1 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 9 9 9
;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99990000000000001 sigma=8.0020000000000007 alpha=est) noplot; run; %show;
