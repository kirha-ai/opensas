/* ERF/ERFC to full f64 precision (was ~1e-7). Regression guard for BUG-erfaccuracy. */
data _null_;
  a = erf(1);
  b = erf(0.5);
  c = erf(2);
  d = erfc(1);
  e = erf(-1);
  put "erf1="  a 16.13;
  put "erf05=" b 16.13;
  put "erf2="  c 16.13;
  put "erfc1=" d 16.13;
  put "erfm1=" e 16.13;
run;
