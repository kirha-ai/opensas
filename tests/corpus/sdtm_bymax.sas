/* Peak (max) value per subject via FIRST./LAST. + RETAIN */
data lb;
  input USUBJID $ VISITNUM AVAL;
  datalines;
01-001 1 30
01-001 2 55
01-001 3 40
01-002 1 50
01-002 2 45
;
run;
proc sort data=lb; by USUBJID VISITNUM; run;
data peak;
  set lb;
  by USUBJID;
  retain pmax;
  if first.USUBJID then pmax = AVAL;
  else if AVAL > pmax then pmax = AVAL;
  if last.USUBJID then output;
  keep USUBJID pmax;
run;
proc print data=peak; run;
