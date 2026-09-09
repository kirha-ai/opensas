/* NOTE-hashemptytype + NOTE-hashoutputnods:
   (1) h.output(dataset:'x') of an EMPTY hash types the output columns from the
       DECLARED defineData variables (length name $ → Char), not from a first
       entry that doesn't exist (was: every column silently Num).
   (2) h.output() with NO dataset: tag logs a loud ERROR and sets rc=1 (was:
       silent rc=1 no-op). The captured-diagnostics half is asserted in
       exec.zig; the loud step comes LAST (a step ERROR poisons later steps,
       BUG-errhalt).
   expect-rc: 1 */
data _null_;
  length k 8;
  length name $ 12;
  declare hash h();
  h.defineKey('k');
  h.defineData('name');
  h.defineDone();
  /* no add(): the hash stays empty */
  rc = h.output(dataset:'empty_out');
  put 'empty rc=' rc;
run;
proc contents data=work.empty_out; run;
data _null_;
  declare hash h2();
  h2.defineKey('k');
  h2.defineData('v');
  h2.defineDone();
  k=1; v='x'; h2.add();
  rc = h2.output(); /* no dataset: — loud ERROR, rc=1 */
  put 'nods rc=' rc;
run;
