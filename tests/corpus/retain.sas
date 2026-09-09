data _null_;
  retain total 0;
  input x;
  total = total + x;
  put "total=" total;
  datalines;
10
20
30
40
;
run;
