/* BUG-arrwriteoor (qa-findings-tick138 BUG-2): an out-of-range array WRITE is
   an execution-time ERROR (SAS 9.4: "ERROR: Array subscript out of range")
   that sets _ERROR_=1 and halts the DATA step at the offending statement —
   not a NOTE + assignment-ignored + continue. Mirrors the read path
   (BUG-arrayoorerror). The ERROR is on stderr (asserted via captured
   diagnostics in exec.zig's test); stdout pins the HALT: the PUT after the
   bad write never runs and the errored step writes no obs.
   expect-rc: 1 */

data _null_;
  array b[-1:1] b1-b3 (10 20 30);
  b[-1] = 99;  /* explicit lo:hi span (GAP-arraybounds): b[-1] is IN span → b1 */
  put b1;      /* 99 — in-span negative-lower-bound writes are fine */
run;

data a;
  array x[3] a1-a3 (1 2 3);
  i = 5;
  x[i] = 9;        /* ERROR: Array subscript out of range — the step stops HERE */
  put 'after-oor'; /* never reached */
run;

data _null_;
  put 'skipped';  /* syntax-check mode (BUG-errhalt): skipped after the ERROR */
run;
