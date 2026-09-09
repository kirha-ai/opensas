/* LB: change and % change from baseline per subject (RETAIN + ROUND) */
data lb;
  input USUBJID $ VISITNUM LBSTRESN;
  datalines;
01-001 1 30
01-001 2 35
01-001 3 40
01-002 1 50
01-002 2 45
;
run;

proc sort data=lb; by USUBJID VISITNUM; run;

data lbchg;
  set lb;
  by USUBJID;
  retain base;
  if first.USUBJID then base = LBSTRESN;
  chg  = LBSTRESN - base;
  pchg = round(100 * chg / base, 0.1);
run;

proc print data=lbchg; run;
