/* Small-n boundary for PROC MEANS SKEWNESS/KURTOSIS: SAS needs n>=3 for
   skewness, n>=4 for kurtosis; below that the statistic is missing (not 0).
   n=2 -> both missing; n=3 -> skewness computed (0 for {1,2,3}), kurtosis
   still missing. Hand-verified vs SAS 9.4. Complements means_skewkurt.sas. */
data d2; input x @@; datalines;
1 2
;
run;
proc means data=d2 n skewness kurtosis; var x; run;
data d3; input x @@; datalines;
1 2 3
;
run;
proc means data=d3 n skewness kurtosis; var x; run;
