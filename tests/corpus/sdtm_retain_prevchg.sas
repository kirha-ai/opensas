/* Change from previous visit via RETAIN of the prior value (no LAG) */
data lb;
  input USUBJID $ VISITNUM AVAL;
  datalines;
01-001 1 30
01-001 2 36
01-001 3 33
01-002 1 50
01-002 2 55
;
run;
proc sort data=lb; by USUBJID VISITNUM; run;
data chg;
  set lb;
  by USUBJID;
  retain prev;
  if first.USUBJID then prev = .;
  chg = AVAL - prev;
  prev = AVAL;
run;
proc print data=chg; var USUBJID VISITNUM AVAL chg; run;
