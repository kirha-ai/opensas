/* Drive a KEEP= from a macro-var variable list (dynamic keep-list) */
data _null_;
  call symputx("keepvars", "USUBJID PARAMCD AVAL");
run;
data lb;
  input USUBJID $ PARAMCD $ AVAL EXTRA;
  datalines;
01-001 ALT 30 999
01-002 AST 25 888
;
run;
data sub;
  set lb;
  keep &keepvars;
run;
proc print data=sub; run;
