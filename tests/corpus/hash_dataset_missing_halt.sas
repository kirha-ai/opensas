/* AUDIT-errhaltclass: `declare hash h(dataset:'<no such table>')` HALTS the
   step instead of reporting the ERROR and running on with an EMPTY hash.

   The old behaviour was the BUG-hashexprdeferredhalt shape wearing a different
   hat: every find() against the empty hash MISSED, so every defineData variable
   stayed MISSING, and the step wrote those fabricated missings to its output.
   Probed on a libname-backed step, it exited 1 and still left
   `code=1,label=.,flag=WROTE` on disk — which a separate run reads back at
   EXIT 0. The nonzero exit does not travel with the data.

   Doc class: Language Reference: Concepts Chapter 8, printed p.172 (most execution-time errors "allow
   the program to continue executing") vs printed p.174-175 Example Code 8.6
   (the ERROR class — "stopped processing this step because of errors" +
   "was not replaced"). A hash that cannot be built is the second.

   The failing step is LAST because a step ERROR errhalt-skips every later step
   (BUG-errhalt). Its stdout side is pinned by this file ending after the
   controls; the halt itself and the untouched PDV are pinned in exec.zig by the
   CAPTURED diagnostics reporter (D-003 — no aborting process is spawned).
   expect-rc: 1 */
data codelist;
  input code label;
  datalines;
1 100
2 200
;
run;

/* Control 1: the SAME construct with a table that EXISTS loads and looks up. */
data _null_;
  length code label 8;
  declare hash lk(dataset:'codelist');
  lk.defineKey('code'); lk.defineData('label'); lk.defineDone();
  code = 2; rc = lk.find();
  put 'control rc=' rc ' label=' label;
run;

/* Control 2: the empty-hash MISS is a legitimate rc, not an error — the halt
   must not swallow the ordinary "key not in the table" case. */
data _null_;
  length code label 8;
  declare hash lk2(dataset:'codelist');
  lk2.defineKey('code'); lk2.defineData('label'); lk2.defineDone();
  code = 99; rc = lk2.find();
  found = (rc = 0);
  put 'miss found=' found;
run;

/* FAILING STEP, LAST: the ERROR is in the log and NOTHING below it runs — no
   PUT, no OUTPUT, no data set. */
data never_written;
  length code label 8 flag $8;
  declare hash broken(dataset:'absent_codelist');
  broken.defineKey('code'); broken.defineData('label'); broken.defineDone();
  code = 1; rc = broken.find();
  flag = 'WROTE';
  put 'hash-dataset step still ran, label=' label;
  output;
run;
