/* NOTE-freqallmissnone: MISSPRINT is supported; keep the prior regression input. */
data h;
  input x;
  datalines;
1
;
run;
proc freq data=h;
  tables x / missprint;
run;
