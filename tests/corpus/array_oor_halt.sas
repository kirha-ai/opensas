/* BUG-arrayoorerror: an out-of-range array subscript is an execution-time
   ERROR (SAS 9.4: "ERROR: Array subscript out of range") that sets _ERROR_=1
   and halts the DATA step at the offending statement — not a soft NOTE +
   set-to-missing + continue. The ERROR is on stderr (asserted via captured
   diagnostics in eval.zig's test); stdout pins the HALT: the PUT after the
   bad subscript never runs.
   expect-rc: 1 */

data _null_;
  array b[-1:1] b1-b3 (10 20 30);
  put b[-1];   /* explicit lo:hi span (GAP-arraybounds): b[-1] is IN span → 10 */
  i = 0;
  put b[i];    /* b[0] in span (folds to element 2) → 20 */
run;

data _null_;
  array a[3] a1-a3 (1 2 3);
  i = 5;
  x = a[i];        /* ERROR: Array subscript out of range — the step stops HERE */
  put 'after-oor'; /* never reached */
run;

data _null_;
  put 'skipped';  /* syntax-check mode (BUG-errhalt): skipped after the ERROR */
run;
