data a;
  input x;
  datalines;
10
20
30
;
run;

data _null_;
  set a nobs=n;
  put "x=" x " n=" n;
run;
