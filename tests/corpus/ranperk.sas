data _null_;
  seed=99;
  a=10; b=20; c=30; d=40;
  call ranperk(seed, 2, a, b, c, d);
  put a b;
run;
