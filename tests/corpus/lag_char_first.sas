/* LAG of a CHARACTER variable on the FIRST obs must be blank (not numeric-missing
   "."); numeric LAG stays "." . Regression guard for BUG-lagcharfirst. */
data _null_;
  input g $ x;
  pg = lag(g);
  px = lag(x);
  put "row=" _n_ " lag_g=[" pg "] lag_x=" px;
  datalines;
A 10
B 20
;
run;
