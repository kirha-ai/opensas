/* Per-arm stat panel in one combined CLASS table (PROC MEANS) */
data vs; input ARM $ AVAL; datalines;
DRUG 120
DRUG 130
DRUG 125
PLACEBO 140
PLACEBO 138
;
run;
proc means data=vs n mean std min max;
  class ARM;
  var AVAL;
run;
