/* NODUPKEY on a two-key sort keeps the first row per (subject, param) */
data lb; input USUBJID $ PARAMCD $ AVAL; datalines;
01-001 ALT 30
01-001 ALT 32
01-001 AST 25
01-002 ALT 50
01-002 ALT 51
;
run;
proc sort data=lb nodupkey out=uniq;
  by USUBJID PARAMCD;
run;
proc print data=uniq; run;
