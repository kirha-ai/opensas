/* N and mean per arm (PROC TABULATE var*(n mean)) */
data lb; input ARM $ AVAL; datalines;
DRUG 30
DRUG 40
DRUG 50
PLACEBO 25
PLACEBO 35
;
run;
proc tabulate data=lb;
  class ARM;
  var AVAL;
  table ARM, AVAL*(N mean);
run;
