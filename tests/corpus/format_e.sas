data _null_;
  a = 1234;         put a e10.;
  b = 12345.678;    put b e10.;
  c = 0.000123;     put c e12.;
  d = -1234;        put d e12.;
  x = 999999999999.9;  put x best12.;
run;
