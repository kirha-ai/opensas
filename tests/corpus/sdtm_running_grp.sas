/* Running cumulative dose per subject via the sum statement (implicit RETAIN) */
data ex;
  input USUBJID $ VISITNUM DOSE;
  datalines;
01-001 1 50
01-001 2 60
01-001 3 40
01-002 1 100
01-002 2 25
;
run;
proc sort data=ex; by USUBJID VISITNUM; run;
data runsum;
  set ex;
  by USUBJID;
  if first.USUBJID then cumdose = 0;
  cumdose + DOSE;
run;
proc print data=runsum; var USUBJID VISITNUM DOSE cumdose; run;
