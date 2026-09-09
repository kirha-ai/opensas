/* Grade against a data-driven ULN threshold captured to a macro var */
data ref; input uln; datalines;
40
;
run;
data _null_;
  set ref;
  call symputx("uln", uln);
run;
data lb;
  input USUBJID $ AVAL;
  datalines;
01-001 30
01-002 55
01-003 42
;
run;
data graded;
  set lb;
  high = (AVAL > &uln);
run;
proc print data=graded; var USUBJID AVAL high; run;
