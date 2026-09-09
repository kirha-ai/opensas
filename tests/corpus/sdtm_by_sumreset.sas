/* Cumulative dose per subject, reset each BY group (sum statement) */
data ex; input USUBJID $ VISITNUM DOSE; datalines;
01-001 1 50
01-001 2 60
01-002 1 100
01-002 2 25
01-002 3 25
;
run;
proc sort data=ex; by USUBJID VISITNUM; run;
data cum;
  set ex;
  by USUBJID;
  if first.USUBJID then cumdose = 0;
  cumdose + DOSE;
run;
proc print data=cum; var USUBJID VISITNUM cumdose; run;
