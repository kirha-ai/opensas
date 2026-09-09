/* BUG-bzinformat / BUG-numembeddedblank: blank handling is INFORMAT-SPECIFIC.
   BZw.d converts every blank (leading/trailing/embedded) to a ZERO; plain w.d
   trims leading/trailing blanks but an EMBEDDED blank is invalid numeric data
   → missing + a NOTE on stderr (the fixture pins the values; the NOTE is
   asserted by the test block in src/format.zig). */
data _null_;
  a = input('1   ', bz4.);   put a=;   /* 1000 — blanks → zeros */
  b = input('2 3 ', 4.);     put b=;   /* . — embedded blank invalid (+NOTE) */
  c = input(' 42 ', 4.);     put c=;   /* 42 — leading/trailing trim OK */
  d = input('  1  ', bz5.);  put d=;   /* 100 — leading blanks → zeros too */
  e = input('1 2', bz3.);    put e=;   /* 102 — embedded blank → zero */
run;
