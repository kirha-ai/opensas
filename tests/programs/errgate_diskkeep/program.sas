/* GAP-errgatereplaces, the CROSS-RUN half: the member exists ONLY ON DISK.

   main's `loadLibInputs` deliberately does NOT preload a `data <libref.x>`
   OUTPUT target, so a member written by an EARLIER RUN is invisible to
   `lib.find` — and that is precisely the clinical case, a failing rerun of
   yesterday's program silently emptying yesterday's data set. The in-Library
   check alone does not cover it; the fix reuses BUG-existdisk's disk probe.

   PROC COPY is the way to stage that state inside ONE run: it writes through
   the libref EAGERLY (GAP-proccopy) and does NOT register `target.survivor` in
   the Library, so when the failing step below runs, the member is on disk and
   nowhere else. Ordinary `data target.x;` output is only flushed at end of run,
   which would not reproduce it.

   Pre-fix, this left output/survivor.csv holding the single column `z` and no
   rows. Re-runnable: PROC COPY rewrites the 3 observations every run.

   BUG-nofixturepinsrc: this fixture's POINT is that the run fails while the
   data survives, so the exit code is half of what it asserts — and until now
   the runner ignored it, so "the outputs are right" would have passed even at
   rc 0. A step error is the user's SAS being wrong: D-009 rc 1.
   expect-rc: 1 */

libname target "output";

data survivor;
  input id k $ v;
  datalines;
1 aa 10
2 bb 20
3 cc 30
;
run;

proc copy in=work out=target;
  select survivor;
run;

/* FAILING STEP, LAST — the undefined-GOTO compile-time gate (exec.zig:3916). */
data target.survivor;
  length z 8;
  goto nowhere;
run;
