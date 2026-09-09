/* GAP-meansskewkurt: PROC MEANS SKEWNESS/KURTOSIS (SAS g1/g2 sample formulas).
   data {1,2,3,4,10}: skew=1.6970563, kurt=3.1520000 (hand-verified vs SAS). */
data d; input x @@; datalines;
1 2 3 4 10
;
run;
proc means data=d skewness kurtosis; var x; run;
