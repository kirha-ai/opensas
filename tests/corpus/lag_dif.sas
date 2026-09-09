data _null_;
  input x;
  l = lag(x);
  d = dif(x);
  put "x=" x " lag=" l " dif=" d;
  datalines;
10
14
19
;
run;
