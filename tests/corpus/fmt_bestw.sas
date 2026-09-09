data _null_;
  a = 12345.678;
  b = 0.000123;
  c = 3.14159;
  put "a=" a best10.;
  put "b=" b best8.;
  put "c=" c best8.;
run;
