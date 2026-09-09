data counts;
  length arm $8;
  input arm $ n;
  datalines;
Active 12
Placebo 8
;
run;
proc freq data=counts; tables arm; weight n; run;
