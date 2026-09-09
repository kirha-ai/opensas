/* AUDIT-errhaltclass / GAP-callexecutehalt: CALL EXECUTE without a single
   character argument HALTS the step instead of reporting and running on.

   Pre-fix, probed on a clean-rebuilt binary:
       data sc.keeper; set sc.keeper; call execute(i); run;
   reported one ERROR per row, ran the step to completion, and REPLACED the live
   3-observation permanent member with its own output — at exit 1, then read
   back by a separate run at exit 0. That is Language Reference: Concepts printed p.174-175 Example
   Code 8.6's "Data set ... was not replaced because this step was stopped",
   inverted.

   HALT CLASS: there is no continuing-class reading. Language Reference: Concepts printed p.172-174
   defines that class by assigning a MISSING VALUE and carrying on; a CALL
   routine that queues a program has no value to make missing — the unit of WORK
   simply does not happen.

   SEVERITY is a separate, still-open question and is NOT changed here
   (ORACLE-callexecutenum). Macro Language: Reference printed p.296 lists only
   CHARACTER forms for `argument`, but its sibling CALL SYMPUT (same chapter,
   printed p.306) auto-converts a numeric "and writes a message in the log", and
   the Functions Reference entry (printed p.303) carries the generic note that
   argument types "must be CHAR, VARCHAR, or NUMERIC" and a mismatch issues a
   WARNING. So real SAS may queue "1" instead of erroring. The halt is safe
   either way: report(.err) already set hasStepErrors(), which errhalt-skips
   every later step AND every queued fragment, so the run was already dead — the
   only delta is that no bogus member is written.

   Failing step LAST (BUG-errhalt errhalt-skips later steps). The captured
   diagnostic, the halt, and the wrong-ARITY form are pinned in exec.zig
   (D-003).
   expect-rc: 1 */
data src;
  input id;
  datalines;
1
2
;
run;

/* Control: a character argument still queues and runs after the current step. */
data _null_;
  put 'main-step';
  call execute('data _null_; put "queued ran"; run;');
run;

/* Control: a character EXPRESSION argument is equally fine. */
data _null_;
  t = 'put "expr queued";';
  call execute('data _null_; ' || t || ' run;');
run;

/* FAILING STEP, LAST: nothing below the CALL EXECUTE runs — no PUT, no row. */
data out_never;
  set src;
  call execute(id);
  put 'numeric-arg step still ran, id=' id;
run;
