data _null_;
  a = round(2.5);
  b = round(0.125, 0.01);
  c = round(-0.125, 0.01);
  d = round(1.045, 0.01);
  e = round(2.675, 0.01);
  put "a=" a " b=" b " c=" c " d=" d " e=" e;
run;
