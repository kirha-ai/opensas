data _null_;
  a = 1e-320;   /* subnormal: 10^320 overflows in reciprocal -> was "infE-319" */
  b = 1e-310;   /* subnormal -> was "infE-308" */
  c = 2.5e-308; /* smallest-ish normal, control */
  put "a=" a;
  put "b=" b;
  put "c=" c;
run;
