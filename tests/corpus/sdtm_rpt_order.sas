/* Ordered detail listing (PROC REPORT display over pre-sorted data) */
data lb; input USUBJID $ PARAMCD $ AVAL; datalines;
01-002 ALT 45
01-001 AST 25
01-001 ALT 30
01-002 AST 35
;
run;
proc sort data=lb; by USUBJID PARAMCD; run;
proc report data=lb nowd;
  column USUBJID PARAMCD AVAL;
  define USUBJID / display;
  define PARAMCD / display;
  define AVAL / display;
run;
