data _null_;
  a = .; b = 5; c = 9;
  x = coalesce(a, b, c);
  p = .; q = .;
  y = coalesce(p, q, 0);
  put "x=" x " y=" y;
run;
