/* Per-parameter ULN thresholds in a _TEMPORARY_ array (high-flag lookup) */
data lb;
  input USUBJID $ PARAMN AVAL;
  datalines;
01-001 1 45
01-002 2 30
01-003 3 200
;
run;
data flag;
  set lb;
  array uln{3} _temporary_ (40 35 150);
  high = (AVAL > uln{PARAMN});
run;
proc print data=flag; var USUBJID PARAMN AVAL high; run;
