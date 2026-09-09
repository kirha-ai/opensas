/* Keep each subject's last visit (IF LAST.) */
data vs; input USUBJID $ VISITNUM AVAL; datalines;
01-001 1 120
01-001 3 118
01-002 1 130
01-002 2 128
;
run;
proc sort data=vs; by USUBJID VISITNUM; run;
data lastvis;
  set vs;
  by USUBJID;
  if last.USUBJID;
run;
proc print data=lastvis; run;
