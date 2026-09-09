data _null_;
  array x{4} x1-x4 (5 10 15 20);
  s = sum(of x{*});
  put "s=" s;
run;
