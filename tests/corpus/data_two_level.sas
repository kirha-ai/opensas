/* G-falsemarkers2 (two_level_name): a two-level DATA target resolves for the WORK
   libref (and any declared libref) — BUG-twolevelread. `data work.foo;` writes to
   WORK.FOO and PROC PRINT reads it back by the same two-level name. */
data work.foo; x=10; y=20; run;
proc print data=work.foo; run;
