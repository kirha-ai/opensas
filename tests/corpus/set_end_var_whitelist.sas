/* NOTE-setendvarwhitelist (QA F4): "`set a end=e;` on a ZERO-ROW input emits
   a FALSE 'variable E in the DROP, KEEP, or RENAME list has never been
   referenced' — the whitelist exempts set_point_var and nobs_var but not
   set_end_var". PROBE VERDICT (clean rebuild, four shapes): the ticket's
   NAMED path (exec.zig assertReferenced) DOES NOT REPRODUCE in ANY shape —
   4d06b298 (BUG-prefixreadflags, tick322) already PDV-defines the end= flag
   at step start (keepReadFlag), so the drop/keep/rename STATEMENT and the
   auto-drop always resolve; b1/b3/b4 below warn nothing. The probe DID
   surface a RESIDUAL the ticket did not name: the output-dataset OPTION
   `data b (drop=e);` FALSE-warns from io.zig's option validator (io.zig:2063,
   "never been referenced"), fed by main.zig:1668 AFTER the step — that root
   is in main.zig, which this audit does not own, so the residual is reported,
   not fixed. The corpus diffs STDOUT only (warnings are stderr), so this
   fixture pins the four shapes' clean stdout; the stderr matrix lives in the
   closing commit message. */
data d; input x; datalines;
1
2
;
run;
data empty; length x 8; delete; run;

data b1;                 /* zero-row plain end= — the ticket's shape: clean */
  set empty end=e1;
run;
data _null_; put 'B1 OK'; run;

data b2 (drop=e2);       /* RESIDUAL: option-form still FALSE-warns (stderr) */
  set d end=e2;
  if e2 then put 'B2 LAST ' x=;
run;

data b3;                 /* drop STATEMENT on the end= var: clean */
  set d end=e3;
  drop e3;
  if e3 then put 'B3 LAST ' x=;
run;

data b4 (keep=x);        /* keep= option NOT naming e: clean control */
  set d end=e4;
run;
data _null_; put 'B4 OK'; run;
