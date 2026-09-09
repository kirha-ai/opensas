/* Last observation carried forward per subject (conditional RETAIN) */
data lb;
  input USUBJID $ VISITNUM LBSTRESN;
  datalines;
01-001 1 30
01-001 2 .
01-001 3 35
01-002 1 50
01-002 2 .
;
run;
proc sort data=lb; by USUBJID VISITNUM; run;
data locf;
  set lb;
  by USUBJID;
  retain last;
  if first.USUBJID then last = .;
  if LBSTRESN ne . then last = LBSTRESN;
  aval = last;
run;
proc print data=locf; var USUBJID VISITNUM LBSTRESN aval; run;
