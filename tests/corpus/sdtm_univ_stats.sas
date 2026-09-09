/* Capture descriptive stats to a dataset (PROC UNIVARIATE OUTPUT) */
data lb; input AVAL; datalines;
10
20
30
40
50
;
run;
proc univariate data=lb noprint;
  var AVAL;
  output out=stats n=n mean=mean std=std min=min max=max median=median;
run;
proc print data=stats; run;
