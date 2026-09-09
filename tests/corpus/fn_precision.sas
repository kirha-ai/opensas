data _null_;
  a = 0.1 + 0.2;
  b = int(2.9999999);
  c = mod(10, 3);
  d = 100000 * 100000;
  put "a=" a " b=" b " c=" c " d=" d;
run;
