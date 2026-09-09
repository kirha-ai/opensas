/* Default (fmterr): an unknown format errors to the log but the run still emits
   the fallback value and continues to the next step
   expect-rc: 1 */
data lb;
  input USUBJID $ AVAL;
  datalines;
01-001 45
;
run;
data d;
  set lb;
  length s $12;
  s = put(AVAL, bogusfmt.);
run;
proc print data=d; var USUBJID AVAL s; run;
