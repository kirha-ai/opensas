/* Descriptive stats for several vitals in one combined table (PROC MEANS) */
data vs; input SYSBP DIABP PULSE; datalines;
120 80 72
130 85 68
140 90 75
;
run;
proc means data=vs n mean std min max;
  var SYSBP DIABP PULSE;
run;
