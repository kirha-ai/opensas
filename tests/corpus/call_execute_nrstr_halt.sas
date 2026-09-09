/* AUDIT-errhaltclass / GAP-callexecutehalt: CALL EXECUTE with a macro-quoting
   function HALTS the step instead of reporting "not supported" and running on.

   This arm is an UNSUPPORTED-FEATURE refusal, not a user mistake: SAS 9.4 Macro
   Language: Reference printed p.296 recommends wrapping a macro invocation in
   %NRSTR inside CALL EXECUTE as the standard workaround for the step-boundary
   problem (the macro is then resolved when the queued text runs, not when the
   CALL EXECUTE statement executes). opensas still cannot honour it (the macro
   facility is gone when the queue drains, FEAT-callexecute/D-002), so CLAUDE.md
   governs: an unsupported feature must error visibly, NEVER no-op. A loud ERROR
   the step then ignores IS a no-op — the step ran every row and wrote its
   output while the queued work never happened.

   There is no continuing-class reading. Language Reference: Concepts printed p.172-174 defines that
   class by assigning a MISSING VALUE and carrying on (division by zero); a CALL
   routine that queues a program has no value to make missing. So it takes the
   p.174-175 Example Code 8.6 path: "stopped processing this step" + "Data set
   … was not replaced".

   Severity is UNCHANGED and was already maximal — report(.err) sets
   hasStepErrors(), which errhalt-skips every later step AND every queued
   fragment — so the only behavioural delta is that the step no longer replaces
   an output member. Probed pre-fix on a clean-rebuilt binary.

   Failing step LAST (BUG-errhalt errhalt-skips later steps). The captured
   diagnostic and the halt itself are pinned in exec.zig (D-003).
   expect-rc: 2 */
data visits;
  input visitno;
  datalines;
1
2
;
run;

/* Control: plain statement text still queues and runs AFTER the current step. */
data _null_;
  put 'outer-step';
  call execute('data _null_; put "deferred ran"; run;');
run;

/* FAILING STEP, LAST: nothing below the CALL EXECUTE runs — no PUT, no row. */
data never_written;
  set visits;
  call execute('%nrstr(%tally_visit(1))');
  put 'nrstr step still ran, visitno=' visitno;
run;
