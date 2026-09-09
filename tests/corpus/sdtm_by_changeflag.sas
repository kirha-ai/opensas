/* Flag a value change from the previous row within a subject (RETAIN + BY) */
data lb; input USUBJID $ VISITNUM NRIND $; datalines;
01-001 1 NORMAL
01-001 2 NORMAL
01-001 3 HIGH
01-002 1 HIGH
01-002 2 NORMAL
;
run;
proc sort data=lb; by USUBJID VISITNUM; run;
data chg;
  set lb;
  by USUBJID;
  length prev $8;
  retain prev;
  if first.USUBJID then prev = "";
  changed = (prev ne "" and NRIND ne prev);
  prev = NRIND;
run;
proc print data=chg; var USUBJID VISITNUM NRIND changed; run;
