data _null_;
  a = 1; b = 2; c = 3;
  s = sum(of a b c);
  put "s=" s;
run;
