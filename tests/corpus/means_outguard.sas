/* GAP-meansoutguards (a): PROC MEANS OUTPUT OUT= with a CLASS var and NO explicit
   statistic list must fail LOUD (ERROR, non-zero exit, run halts) — never emit the
   misleading overall-only long form that silently drops the `g` column and the
   _TYPE_ bitmask rows. The PROC PRINT below is a regression tripwire: if the guard
   is removed, the bogus overall-only `o` leaks to stdout and fails this fixture.
   Correct (guarded) behavior: the run stops at the MEANS error, stdout stays empty.
   expect-rc: 1 */
data d;
  do g = 1 to 2;
    x = g;
    output;
  end;
run;
proc means data=d;
  class g;
  output out=o;
run;
proc print data=o noobs;
run;
