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
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99999899999999997 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_001; data d; input x @@; datalines;
1 5 5 5 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99990000000000001 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_002; data d; input x @@; datalines;
1 5 5 5 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.999 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_003; data d; input x @@; datalines;
1 5 5 5 5 5 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99999899999999997 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_004; data d; input x @@; datalines;
1 5 5 5 5 5 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99990000000000001 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_005; data d; input x @@; datalines;
1 5 5 5 5 5 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.999 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_006; data d; input x @@; datalines;
1 5 5 5 5 5 5 5 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99999899999999997 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_007; data d; input x @@; datalines;
1 5 5 5 5 5 5 5 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99990000000000001 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_008; data d; input x @@; datalines;
1 5 5 5 5 5 5 5 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.999 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_009; data d; input x @@; datalines;
1 5 5 5 5 5 5 5 5 5 5 5 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99999899999999997 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_010; data d; input x @@; datalines;
1 5 5 5 5 5 5 5 5 5 5 5 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99990000000000001 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_011; data d; input x @@; datalines;
1 5 5 5 5 5 5 5 5 5 5 5 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.999 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_012; data d; input x @@; datalines;
1 10 10 10 10 10 19
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99990000000000001 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_013; data d; input x @@; datalines;
1 10 10 10 10 10 19
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99970000000000003 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_014; data d; input x @@; datalines;
1 10 10 10 10 10 19
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.999 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_015; data d; input x @@; datalines;
1 10 10 10 10 10 19
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99850000000000005 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_016; data d; input x @@; datalines;
1 10 10 10 10 10 10 10 19
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99990000000000001 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_017; data d; input x @@; datalines;
1 10 10 10 10 10 10 10 19
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99970000000000003 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_018; data d; input x @@; datalines;
1 10 10 10 10 10 10 10 19
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.999 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_019; data d; input x @@; datalines;
1 10 10 10 10 10 10 10 19
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99850000000000005 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_020; data d; input x @@; datalines;
1 1 5 5 5 5 5 5 5 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99990000000000001 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_021; data d; input x @@; datalines;
1 1 5 5 5 5 5 5 5 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.999 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_022; data d; input x @@; datalines;
1 5 5 5 5 5 5 5 9 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99990000000000001 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_023; data d; input x @@; datalines;
1 5 5 5 5 5 5 5 9 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.999 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_024; data d; input x @@; datalines;
1 1 5 5 5 5 5 5 5 9 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99990000000000001 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_025; data d; input x @@; datalines;
1 1 5 5 5 5 5 5 5 9 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.999 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_026; data d; input x @@; datalines;
1 4.7999999999999998 4.9000000000000004 5 5 5 5.0999999999999996 5.2000000000000002 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99999899999999997 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_027; data d; input x @@; datalines;
1 4.7999999999999998 4.9000000000000004 5 5 5 5.0999999999999996 5.2000000000000002 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99990000000000001 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_028; data d; input x @@; datalines;
1 4.7999999999999998 4.9000000000000004 5 5 5 5.0999999999999996 5.2000000000000002 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.999 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_029; data d; input x @@; datalines;
7 47 47 47 47 47 47 47 87
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=6.9989999999999997 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_030; data d; input x @@; datalines;
7.0999999999999996 7.5 7.5 7.5 7.5 7.5 7.5 7.5 7.9000000000000004
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=7.09999 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_031; data d; input x @@; datalines;
1 1 1 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 9 9 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99990000000000001 sigma=est alpha=est) noplot; run; %show;
%let case=mixture_032; data d; input x @@; datalines;
1 5 5 5 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99999899999999997 sigma=est alpha=0.5) noplot; run; %show;
%let case=mixture_033; data d; input x @@; datalines;
1 5 5 5 5 5 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99999899999999997 sigma=est alpha=0.5) noplot; run; %show;
%let case=mixture_034; data d; input x @@; datalines;
1 10 10 10 10 10 19
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99990000000000001 sigma=est alpha=0.5) noplot; run; %show;
%let case=mixture_035; data d; input x @@; datalines;
1 10 10 10 10 10 10 10 19
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=0.99990000000000001 sigma=est alpha=0.5) noplot; run; %show;
