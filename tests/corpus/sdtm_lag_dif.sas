/* Visit-over-visit change via DIF (per subject, blank at first visit) */
data lb;
  input USUBJID $ VISITNUM LBSTRESN;
  datalines;
01-001 1 30
01-001 2 36
01-001 3 40
01-002 1 50
01-002 2 47
;
run;
proc sort data=lb; by USUBJID VISITNUM; run;
data d;
  set lb;
  by USUBJID;
  change = dif(LBSTRESN);
  if first.USUBJID then change = .;
run;
proc print data=d; var USUBJID VISITNUM LBSTRESN change; run;
