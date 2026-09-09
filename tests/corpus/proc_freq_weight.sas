/* QA regression (BUG-freqweight fixed): PROC FREQ WEIGHT statement — Frequency is
   the sum of weights per category, Percent over the weighted total. */
data d;
  input cat $ wt;
  datalines;
A 3
A 2
B 5
C 10
;
run;

proc freq data=d;
  tables cat;
  weight wt;
run;
