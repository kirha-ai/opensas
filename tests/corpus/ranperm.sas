data _null_;
  seed=12345;
  a=1; b=2; c=3; d=4;
  call ranperm(seed, a, b, c, d);
  put a b c d;
run;
