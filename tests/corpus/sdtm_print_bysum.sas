/* Per-arm listing with a subtotal (PROC PRINT BY + SUM) */
data ex;
  input ARM $ USUBJID $ EXDOSE;
  datalines;
DRUG 01-001 50
DRUG 01-002 100
PLACEBO 01-003 0
PLACEBO 01-004 0
;
run;
proc sort data=ex; by ARM; run;
proc print data=ex;
  by ARM;
  var USUBJID EXDOSE;
  sum EXDOSE;
run;
