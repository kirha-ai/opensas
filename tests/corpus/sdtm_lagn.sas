/* Value one and two visits back (LAG1/LAG2) */
data lb;
  input USUBJID $ AVAL;
  datalines;
01-001 10
01-001 20
01-001 30
01-001 40
;
run;
data d;
  set lb;
  prev1 = lag1(AVAL);
  prev2 = lag2(AVAL);
run;
proc print data=d; var AVAL prev1 prev2; run;
