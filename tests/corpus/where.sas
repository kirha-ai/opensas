data have;
  input x;
  datalines;
5
12
3
20
;
run;

data big;
  set have;
  where x > 10;
run;

data _null_;
  set big;
  put "x=" x;
run;
