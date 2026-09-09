/* GAP-rankguards: an unimplemented RANK score option (FRACTION) must fail LOUD
   (ERROR on stderr, non-zero exit) and halt — NEVER silently emit ordinal ranks.
   The PROC PRINT below is a regression tripwire: if the guard is ever removed,
   `o` gets bogus ordinal ranks and they leak to stdout, failing this fixture.
   Correct (guarded) behavior: the run stops at the RANK error, stdout stays empty.
   expect-rc: 2 */
data have;
  input x;
  datalines;
10
20
30
40
;
run;
proc rank data=have out=o fraction;
  var x;
  ranks fr;
run;
proc print data=o noobs;
run;
