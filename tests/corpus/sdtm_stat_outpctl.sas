/* Median and quartiles captured to a dataset (PROC MEANS OUTPUT) */
data vs; input AVAL; datalines;
10
20
30
40
50
;
run;
proc means data=vs noprint;
  var AVAL;
  output out=stats(drop=_type_ _freq_) median=med q1=q1 q3=q3 mean=mean;
run;
proc print data=stats; run;
