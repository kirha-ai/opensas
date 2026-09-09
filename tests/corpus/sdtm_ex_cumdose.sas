/* Cumulative dose per subject (RETAIN accumulation across visits) */
data ex;
  input USUBJID $ EXDY EXDOSE;
  datalines;
01-001 1 50
01-001 8 50
01-001 15 100
01-002 1 75
01-002 8 75
;
run;

proc sort data=ex; by USUBJID EXDY; run;

data cum;
  set ex;
  by USUBJID;
  retain cumdose;
  if first.USUBJID then cumdose = 0;
  cumdose = cumdose + EXDOSE;
run;

proc print data=cum; var USUBJID EXDY EXDOSE cumdose; run;
