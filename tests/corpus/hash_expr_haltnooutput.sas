/* BUG-hashexprdeferredhalt: a hash expression that CANNOT BE EVALUATED must
   stop the step where it fails — it must not fabricate a return code, take a
   branch on it, and write records that look real.

   The old hashOp error path reported the ERROR and then `return`ed normally
   after setting the rc target to 1 (the GAP-hashmethods "defined non-zero rc"
   rule, 991ba598). Defined, but INVENTED: `if ghost.check = 1` compares against
   that very 1, so the THEN branch ran, the step ran to completion, and the
   ERROR only surfaced afterwards. stdout got "BRANCH TAKEN" and "AFTER" first.
   Worse than the PUT shape: the same step WROTE ITS OUTPUT DATA SET, so a
   later run read a permanent `flag=taken` back with exit 0 — the nonzero exit
   does not travel with the data.

   Language Reference: Concepts printed p.172 ("Execution-Time Errors"): "Most execution-time errors
   produce warning messages or notes in the SAS log but allow the program to
   continue executing", footnote 1 — "more serious errors can cause SAS to
   enter syntax check mode and stop processing the program". Printed p.173-174
   is the continuing class (division by 0: "SAS executes the entire step,
   assigns a missing value"); printed p.174-175 Example Code 8.6 is the ERROR
   class — an out-of-range array subscript, then "NOTE: The SAS System
   stopped processing this step because of errors" and a "was not replaced
   because this step was stopped" WARNING for the output data set. A hash
   failure is reported at ERROR severity, so it takes the p.174-175 path.

   This .txt pins the STDOUT side, which is the half that asserting the ERROR
   alone would miss: the controls below must print, and the failing step must
   print NOTHING. The ERROR itself goes to stderr and is asserted by the
   captured-diagnostics `test` blocks in src/exec.zig (D-003 — no corpus
   fixture spawns an aborting process to check a diagnostic). Per BUG-errhalt a
   step ERROR puts every later step into syntax-check mode, so the failing step
   must come LAST (same shape as sql_lag_failloud).
   expect-rc: 1 */

/* Controls — the WORKING hash-in-expression path is unmoved by the halt. */
data _null_;
  length armno 8 arm $8;
  declare hash arms();
  arms.defineKey("armno");
  arms.defineData("arm");
  arms.defineDone();
  rc = arms.add(key: 1, data: "placebo");
  rc = arms.add(key: 2, data: "active");
  armno = 1;
  if arms.find() = 0 then put "control hit  arm=" arm;
  armno = 9;
  if arms.find() = 0 then put "control hit2 arm=" arm;
  else put "control miss";
  /* a rc that legitimately EQUALS the old fabricated 1 must still be readable */
  if arms.num_items = 2 then put "control items";
  put "control after";
run;

/* The ticket's shape. `ghost` is an UNDECLARED hash object, so the condition
   has no value. Neither line below may reach stdout: if either appears, the
   step ran past an unevaluable condition. */
data _null_;
  if ghost.check = 1 then put "BRANCH TAKEN - BUG";
  put "AFTER - BUG";
run;
