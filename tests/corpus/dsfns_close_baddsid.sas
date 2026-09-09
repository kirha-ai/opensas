/* Regression: BUG-dsfnsclose — close() on a bad dataset id must not panic.
   A missing (NaN), huge, or zero dsid once slipped the guard and aborted
   (SIGABRT) via @intFromFloat. Now every bad id returns -1. */
data _null_;
  rc1 = close(.);
  rc2 = close(999999999999999999999);
  rc3 = close(0);
  put "rc1=" rc1 " rc2=" rc2 " rc3=" rc3;
run;
