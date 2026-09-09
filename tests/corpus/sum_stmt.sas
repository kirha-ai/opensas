data _null_;
  input x;
  total + x;
  put "x=" x " total=" total;
  datalines;
10
.
30
;
run;
