/* First/last within nested BY groups (subject, then parameter) */
data lb;
  input USUBJID $ PARAM $ VISITNUM AVAL;
  datalines;
01-001 ALT 1 30
01-001 ALT 2 40
01-001 AST 1 25
01-002 ALT 1 50
01-002 ALT 2 55
;
run;
proc sort data=lb; by USUBJID PARAM VISITNUM; run;
data endpts;
  set lb;
  by USUBJID PARAM;
  if last.PARAM then output;
  keep USUBJID PARAM AVAL;
run;
proc print data=endpts; run;
