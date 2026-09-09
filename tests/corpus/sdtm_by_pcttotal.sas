/* Each visit's dose as a percent of the subject's total (two-pass RETAIN + MERGE) */
data ex;
  input USUBJID $ VISITNUM EXDOSE;
  datalines;
01-001 1 50
01-001 2 100
01-001 3 50
01-002 1 75
01-002 2 25
;
run;
proc sort data=ex; by USUBJID VISITNUM; run;
proc means data=ex noprint nway;
  class USUBJID;
  var EXDOSE;
  output out=tot(keep=USUBJID total) sum=total;
run;
data pct;
  merge ex tot;
  by USUBJID;
  pcttot = round(100 * EXDOSE / total, 0.1);
run;
proc print data=pct; var USUBJID VISITNUM EXDOSE total pcttot; run;
