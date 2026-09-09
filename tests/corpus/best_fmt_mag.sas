data _null_;
  a = 1e13;             /* too big for fixed -> E */
  b = 12345678901234;   /* 14 digits -> E with rounded mantissa */
  c = 123456789012;     /* 12 digits -> fits as integer */
  d = 1e-11;            /* too small for fixed -> E */
  e = 1/3e8;            /* E shows more sig digits than fixed */
  f = -1e13;            /* negative large -> E */
  put "a=" a;
  put "b=" b;
  put "c=" c;
  put "d=" d;
  put "e=" e;
  put "f=" f;
run;
