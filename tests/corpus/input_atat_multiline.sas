data d;
  input x @@;
  datalines;
1 2 3 4 5
6 7 8
;
run;
data _null_;
  set d end=last;
  n + 1;
  put "x=" x;
  if last then put "count=" n;
run;
