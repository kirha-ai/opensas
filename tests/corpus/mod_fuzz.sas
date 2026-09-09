/* MOD fuzzing (BUG-modnofuzz): MOD snaps FP dust to 0, MODZ stays exact */
data _null_;
  a = mod(0.3, 0.1);  /* SAS: 0 (fuzzed) */
  b = mod(0.6, 0.2);  /* SAS: 0 (fuzzed) */
  c = mod(10, 3);     /* exact integer remainder, unchanged */
  d = mod(-7, 3);     /* sign of dividend, unchanged */
  e = modz(0.3, 0.1); /* MODZ: no fuzzing — dust leaks through */
  f = modz(10, 3);
  put "a=" a " b=" b " c=" c " d=" d;
  put "e=" e best20. " f=" f;
run;
