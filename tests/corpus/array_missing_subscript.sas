/* BUG-arraysubmissing: a MISSING (.) / NaN array subscript is out of range
   (SAS 9.4: "ERROR: Array subscript out of range") — it sets _ERROR_=1 and
   HALTS the step, on BOTH the read (x=a{i}) and the write (a{i}=99) paths.
   Previously the NaN case was exempted from the OOR guard (BUG-arrayoorerror)
   and silently yielded/ignored missing — the exact silent-wrong class that
   guard was filed to kill. A valid integer subscript and a fractional in-range
   subscript (truncated toward zero, a{2.9}->a{2}) still work.

   The ERROR is on stderr (asserted via the captured-diagnostics test blocks in
   eval.zig for the read path and exec.zig for the write path); stdout here pins
   the POSITIVES and the HALT — the PUT after the bad access never runs, and the
   step that follows the first ERROR is skipped in syntax-check mode.
   expect-rc: 1 */

/* positives: a valid integer subscript and an in-range fractional one both work */
data _null_;
  array a{3} (10 20 30);
  k = 2.9;
  put a{2};   /* 20 */
  put a{k};   /* 20 — 2.9 truncates to element 2, NOT a missing */
run;

/* WRITE path: a{i}=99 with i=. is out of range -> ERROR, the step halts HERE */
data w;
  array a{3} (10 20 30);
  i = .;
  a{i} = 99;          /* ERROR: Array subscript out of range — stops HERE */
  put 'after-write';  /* never reached */
run;

/* READ path: skipped in syntax-check mode after the first ERROR (BUG-errhalt);
   its fail-loud is asserted in eval.zig. Same missing-subscript OOR either way. */
data _null_;
  array a{3} (10 20 30);
  i = .;
  x = a{i};           /* would ERROR too */
  put 'after-read';
run;
