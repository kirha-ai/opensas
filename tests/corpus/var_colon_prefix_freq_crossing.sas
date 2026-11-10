/* GAP-freq-table-complete: supported table syntax regression. */
data t;
  x1 = 1; x2 = 2; y = 3;
run;
proc freq data=t;
  tables x:*y;
run;
