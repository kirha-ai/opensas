/* Per-arm total dose (PROC REPORT group + analysis sum) */
data ex; input ARM $ USUBJID $ EXDOSE; datalines;
DRUG 01-001 50
DRUG 01-002 100
PLACEBO 01-003 0
PLACEBO 01-004 25
;
run;
proc report data=ex nowd;
  column ARM EXDOSE;
  define ARM / group;
  define EXDOSE / analysis sum;
run;
