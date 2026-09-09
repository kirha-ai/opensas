/* Overall descriptive stats, no class (PROC MEANS whole dataset) */
data lb; input AVAL; datalines;
12
18
24
30
36
;
run;
proc means data=lb n mean median std min max sum;
  var AVAL;
run;
