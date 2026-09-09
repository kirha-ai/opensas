data out(keep=x);
  x = 1;
  y = 2;
run;

data _null_;
  set out;
  put "x=" x;
run;
