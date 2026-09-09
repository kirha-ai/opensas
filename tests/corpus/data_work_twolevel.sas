data foo;
  x = 1; output;
  x = 2; output;
run;
data _null_;
  set work.foo;
  put "x=" x;
run;
