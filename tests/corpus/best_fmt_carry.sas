data _null_;
  a = 9.9999999999e13;   /* mantissa rounds to 10 -> renormalize to 1E14 */
  b = 9.9999999e-12;     /* small side: mantissa carry bumps exponent */
  c = -9.9999999999e13;  /* negative, same carry */
  d = 1e13;              /* control: no carry */
  put "a=" a;
  put "b=" b;
  put "c=" c;
  put "d=" d;
run;
