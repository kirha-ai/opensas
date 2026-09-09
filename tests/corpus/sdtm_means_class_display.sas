/* Descriptive stats per arm in one combined table (PROC MEANS CLASS display) */
data vs;
  input ARM $ VSSTRESN;
  datalines;
DRUG 120
DRUG 130
DRUG 125
PLACEBO 140
PLACEBO 138
;
run;
proc means data=vs n mean std min max;
  class ARM;
  var VSSTRESN;
run;
