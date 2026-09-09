/* Long-to-wide: one row per subject, a column per lab test (PROC TRANSPOSE) */
data lb;
  input USUBJID $ LBTESTCD $ LBSTRESN;
  datalines;
01-001 ALT 30
01-001 AST 25
01-002 ALT 45
01-002 AST 35
;
run;
proc sort data=lb; by USUBJID; run;
proc transpose data=lb out=wide;
  by USUBJID;
  id LBTESTCD;
  var LBSTRESN;
run;
proc print data=wide; run;
