/* options nofmterr: a typo'd format falls back silently instead of halting */
options nofmterr;
data lb;
  input USUBJID $ AVAL;
  datalines;
01-001 45
01-002 30
;
run;
data d;
  set lb;
  length s $12;
  s = put(AVAL, undefinedfmt.);
run;
proc print data=d; var USUBJID AVAL s; run;
