/* Regression: PROC FREQ orders NUMERIC class levels numerically (1,2,10),
   not lexically (1,10,2). Guards against the TABULATE lexical-order bug
   (BUG-tabnumorder) spreading to FREQ. */
data d;
  input g;
  datalines;
1
2
10
2
10
10
;
run;
proc freq data=d; tables g; run;
