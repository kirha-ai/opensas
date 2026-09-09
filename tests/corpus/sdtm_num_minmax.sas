/* MIN/MAX/LARGEST/SMALLEST across visit readings */
data vs;
  input USUBJID $ v1 v2 v3 v4;
  datalines;
01-001 120 145 118 132
01-002 130 128 140 125
;
run;
data d;
  set vs;
  lo  = min(v1, v2, v3, v4);
  hi  = max(v1, v2, v3, v4);
  hi2 = largest(2, v1, v2, v3, v4);
  lo2 = smallest(2, v1, v2, v3, v4);
run;
proc print data=d; var USUBJID lo hi hi2 lo2; run;
