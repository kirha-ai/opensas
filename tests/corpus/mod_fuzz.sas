/* MOD fuzzing (BUG-modnofuzz): MOD snaps FP dust to 0, MODZ stays exact */
data _null_;
  a = mod(0.3, 0.1);  /* SAS: 0 (fuzzed) */
  b = mod(0.6, 0.2);  /* SAS: 0 (fuzzed) */
  c = mod(10, 3);     /* exact integer remainder, unchanged */
  d = mod(-7, 3);     /* sign of dividend, unchanged */
  e = modz(0.3, 0.1); /* MODZ: no fuzzing — dust leaks through: 0.09999999999999998,
                         which SAS 9.4 BEST20. still DISPLAYS as 0.1 (STAT-BEST-001) */
  f = modz(10, 3);
  put "a=" a " b=" b " c=" c " d=" d;
  put "e=" e best20. " f=" f;
  put "e_bits=" e hex16.; /* the dust itself: 3FB9999999999998, not 0.1 */
run;
