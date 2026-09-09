/* Long-to-wide: lab params to columns per subject (PROC TRANSPOSE ID) */
data lb;
  input USUBJID $ PARAMCD $ AVAL;
  datalines;
01-001 ALT 30
01-001 AST 25
01-001 BILI 5
01-002 ALT 45
01-002 AST 35
01-002 BILI 8
;
run;
proc sort data=lb; by USUBJID; run;
proc transpose data=lb out=wide(drop=_name_);
  by USUBJID;
  id PARAMCD;
  var AVAL;
run;
proc print data=wide; run;
