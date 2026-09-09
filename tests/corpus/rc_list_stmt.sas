/* GAP-gapsexitingone §5d — the DATA-step LIST statement (echo the current
   input record to the log) is documented valid SAS 9.4 that opensas does not
   implement: valid SAS refused → gap → rc 2, not 1. The guard is the keyword
   itself (a variable NAMED list still parses — main.zig GAP-liststmt test),
   so no typo arm. The step ERROR errhalt-skips only later steps, so the
   leading PRINT keeps the golden non-empty.
   expect-rc: 2 */
data a;
  x = 1;
run;
proc print data=a;
run;
data b;
  input y;
  list;
datalines;
1
;
run;
