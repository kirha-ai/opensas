/* RANUNI reproduces SAS's exact seeded Lehmer/MINSTD sequence (multiplier 16807).
   Regression guard for BUG-ranseq. */
data _null_;
  a = ranuni(1);
  b = ranuni(1);
  c = ranuni(1);
  put "r1=" a 14.10;
  put "r2=" b 14.10;
  put "r3=" c 14.10;
run;
