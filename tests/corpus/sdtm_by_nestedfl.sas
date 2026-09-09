/* FIRST./LAST. on nested BY groups (subject, then parameter) */
data lb; input USUBJID $ PARAMCD $ VISITNUM AVAL; datalines;
01-001 ALT 1 30
01-001 ALT 2 40
01-001 AST 1 25
01-002 ALT 1 50
;
run;
proc sort data=lb; by USUBJID PARAMCD VISITNUM; run;
data ends;
  set lb;
  by USUBJID PARAMCD;
  if last.PARAMCD then output;
  keep USUBJID PARAMCD AVAL;
run;
proc print data=ends; run;
