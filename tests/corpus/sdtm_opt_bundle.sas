/* A bundle of global options is accepted (no-op) and the program runs normally */
options nodate nonumber linesize=80 pagesize=60 validvarname=v7;
data vs;
  input ARM $ AVAL;
  datalines;
DRUG 120
DRUG 130
PLACEBO 140
;
run;
proc means data=vs n mean;
  class ARM;
  var AVAL;
run;
