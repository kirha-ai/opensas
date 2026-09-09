/* BUG-inputmultistmt: two INPUT statements in one step accumulate their var
   lists, so columns appear in first-appearance order (x y z), not just the
   last statement's (z). Each plain INPUT reads a fresh record, so the two
   data values below sit on separate lines. */
data t;
  input x y;
  input z;
  datalines;
1 2
3
;
run;
proc print data=t; run;
