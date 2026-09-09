data _null_;
  retain total 0;
  input x;
  total = total + x;
  prev = lag(x);
  put "x=" x " total=" total " prev=" prev;
  datalines;
10
20
30
;
run;
