/* Baseline flag: merge each record with its subject's first visit (self-merge BY) */
data lb;
  input USUBJID $ VISITNUM AVAL;
  datalines;
01-001 1 30
01-001 2 40
01-002 1 50
01-002 2 55
;
run;
proc sort data=lb; by USUBJID VISITNUM; run;
data base(keep=USUBJID base);
  set lb;
  by USUBJID;
  if first.USUBJID then base = AVAL;
  if first.USUBJID then output;
run;
data chg;
  merge lb base;
  by USUBJID;
  chg = AVAL - base;
run;
proc print data=chg; var USUBJID VISITNUM AVAL base chg; run;
