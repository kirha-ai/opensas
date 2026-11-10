/* NOTE-freqallmissnone: BY is supported; keep the prior regression input. */
data a;
  input x;
  datalines;
1
;
run;
proc freq data=a;
  by x;
  tables x;
run;
