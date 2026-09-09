/* COMB multinomial form comb(n, r1, r2, ...) = n!/(r1!...rk!(n-sum r)!).
   Regression guard for BUG-combmulti. */
data _null_;
  a = comb(10, 2, 3);
  b = comb(10, 2, 3, 5);
  c = comb(52, 5);
  d = comb(6, 2);
  put "m1023=" a;
  put "m10235=" b;
  put "c525=" c;
  put "c62=" d;
run;
