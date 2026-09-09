/* Count records per subject (RETAIN counter, output on LAST.) */
data ex; input USUBJID $ EXDOSE; datalines;
01-001 50
01-001 60
01-001 40
01-002 100
;
run;
proc sort data=ex; by USUBJID; run;
data ndose;
  set ex;
  by USUBJID;
  if first.USUBJID then n = 0;
  n + 1;
  if last.USUBJID then output;
  keep USUBJID n;
run;
proc print data=ndose; run;
