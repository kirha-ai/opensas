data _null_;
  a = round(2.5);
  b = round(3.14159, 0.01);
  c = round(1234, 100);
  d = round(2.567, 0.1);
  e = round(-2.5);
  put "a=" a " b=" b " c=" c " d=" d " e=" e;
run;
