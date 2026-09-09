data _null_;
  a = 0.1234;
  b = 0.5;
  c = 1.5;
  put "a=" a percent8.1;
  put "b=" b percent10.2;
  put "c=" c percent8.;
run;
