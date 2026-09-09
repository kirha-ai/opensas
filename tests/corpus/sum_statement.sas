data _null_;
  input x @@;
  total + x;
  put "x=" x "running_total=" total;
  datalines;
10 20 . 30
;
run;
