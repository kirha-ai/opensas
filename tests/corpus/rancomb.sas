data _null_;
  seed=54321;
  a=1; b=2; c=3; d=4; e=5;
  call rancomb(seed, 3, a, b, c, d, e);
  put a b c;
run;
