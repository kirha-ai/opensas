/* Mean vital per arm (PROC TABULATE class, var*mean) */
data vs; input ARM $ AVAL; datalines;
DRUG 120
DRUG 130
PLACEBO 138
PLACEBO 142
;
run;
proc tabulate data=vs;
  class ARM;
  var AVAL;
  table ARM, AVAL*mean;
run;
