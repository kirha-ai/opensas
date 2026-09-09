/* Change from previous visit via LAG (per subject) */
data lb;
  input USUBJID $ VISITNUM LBSTRESN;
  datalines;
01-001 1 30
01-001 2 36
01-001 3 33
01-002 1 50
01-002 2 55
;
run;

proc sort data=lb; by USUBJID VISITNUM; run;

data lbdelta;
  set lb;
  by USUBJID;
  prev = lag(LBSTRESN);
  if first.USUBJID then delta = .;
  else delta = LBSTRESN - prev;
run;

proc print data=lbdelta; var USUBJID VISITNUM LBSTRESN delta; run;
