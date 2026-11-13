options nonumber nodate;
%macro show;
%put DEV3_CASE &case;
%if %sysfunc(exist(p)) %then %do;
data _null_; set p; put 'DEV3_PARAMETER ' Symbol $ ' ' Estimate hex16.; run;
proc datasets lib=work nolist; delete p; quit;
%end;
%mend;
%let case=initial_edge_00; data d; input x @@; datalines;
1 1 1 1 1 1 1 20
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=.9999 sigma=est alpha=est) noplot; run; %show;
%let case=initial_edge_01; data d; input x @@; datalines;
1 1 1 1 1 1 1 20
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=.9999 sigma=est alpha=0.5) noplot; run; %show;
%let case=initial_edge_02; data d; input x @@; datalines;
1 1 1 1 20 20 20 20
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=.9999 sigma=est alpha=est) noplot; run; %show;
%let case=initial_edge_03; data d; input x @@; datalines;
1 1 1 1 20 20 20 20
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=.9999 sigma=est alpha=0.5) noplot; run; %show;
%let case=initial_edge_04; data d; input x @@; datalines;
1 5 5 5 5 5 5 5 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=.9999 sigma=est alpha=est) noplot; run; %show;
%let case=initial_edge_05; data d; input x @@; datalines;
1 5 5 5 5 5 5 5 9
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=.9999 sigma=est alpha=0.5) noplot; run; %show;
%let case=initial_edge_06; data d; input x @@; datalines;
1 1.01 1.02 1.03 20
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=.9999 sigma=est alpha=est) noplot; run; %show;
%let case=initial_edge_07; data d; input x @@; datalines;
1 1.01 1.02 1.03 20
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=.9999 sigma=est alpha=0.5) noplot; run; %show;
%let case=initial_edge_08; data d; input x @@; datalines;
1 1 1 2
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=.9999 sigma=est alpha=est) noplot; run; %show;
%let case=initial_edge_09; data d; input x @@; datalines;
1 1 1 2
;
%put DEV3_SAMPLE_CASE &case; data _null_; set d; put 'DEV3_SAMPLE ' x hex16.; run;
title "&case"; ods output ParameterEstimates=p; proc univariate data=d noprint; histogram x / power(theta=.9999 sigma=est alpha=0.5) noplot; run; %show;
