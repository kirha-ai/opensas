/* Keep each subject's first (baseline) visit only (IF FIRST.) */
data vs; input USUBJID $ VISITNUM AVAL; datalines;
01-001 1 120
01-001 2 125
01-002 1 130
01-002 2 128
01-003 1 118
;
run;
proc sort data=vs; by USUBJID VISITNUM; run;
data baseline;
  set vs;
  by USUBJID;
  if first.USUBJID;
run;
proc print data=baseline; run;
