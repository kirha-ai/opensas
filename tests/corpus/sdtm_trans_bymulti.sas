/* Transpose within two BY keys (subject x visit -> params across) */
data lb; input USUBJID $ VISITNUM PARAMCD $ AVAL; datalines;
01-001 1 ALT 30
01-001 1 AST 25
01-001 2 ALT 40
01-001 2 AST 28
;
run;
proc sort data=lb; by USUBJID VISITNUM; run;
proc transpose data=lb out=wide(drop=_name_);
  by USUBJID VISITNUM;
  id PARAMCD;
  var AVAL;
run;
proc print data=wide; run;
