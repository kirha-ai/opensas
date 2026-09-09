/* BUG-fmttimeoverflow: TIME shows cumulative hours, so >=100h times render
   3-digit hh wider than the pad width — must not panic. Negative is
   SAS-defined (leading minus). */
data _null_;
  t100 = '100:00:00't;
  t99  = 359999;
  tn   = -360000;
  norm = '14:45:32't;
  put t100 time.;   /* 100h: default width 8, content 9 — no truncate, no panic */
  put t100 time8.;  /* same value, explicit width */
  put t100 time11.; /* wide field, right-justified */
  put t99  time8.;  /* 99:59:59 — pre-existing path, byte-identical */
  put norm time8.;  /* normal time, unchanged */
  put tn   time.;   /* negative: -100:00:00 */
run;
