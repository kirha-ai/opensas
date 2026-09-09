/* GREEN lock (qa tick231): one-pass hashed one-way FREQ (PERF-freqoneway).
   ORDER=FREQ with a WEIGHTED count tie must break by ASCENDING value, and
   non-positive/zero weights must not inflate a level. Locks the oneWayLevels
   accumulation + FreqCtx tie-break the perf refactor introduced. */
data t;
  input c $ wt;
  datalines;
b 3
a 2
c 4
a 1
b 0
c -5
d 3
b 0
;
run;
/* weighted counts: a=3, b=3, c=4, d=3 (b's two 0-wt rows keep level, add 0;
   c's -5 row excluded). order=freq: c(4) first, then a,b,d tie at 3 broken
   by ascending value -> a,b,d. */
proc freq data=t order=freq;
  tables c;
  weight wt;
run;
