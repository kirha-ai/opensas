/* Quartiles to a dataset (PROC UNIVARIATE OUTPUT percentiles) */
data vs; input AVAL; datalines;
10
20
30
40
;
run;
proc univariate data=vs noprint;
  var AVAL;
  output out=q p25=q1 p50=median p75=q3;
run;
proc print data=q; run;
