/* GAP-errgatereplaces — a step STOPPED by an error must not REPLACE an existing
   member, but must still CREATE one for a NEW name. Both halves in ONE step,
   because a step ERROR errhalt-skips every later step (BUG-errhalt), so a
   fixture gets exactly one failing step and it has to be last.

   Language Reference: Concepts printed p.175 (Example Code 8.6, pdf index 192, offset +17):
     "WARNING: Data set WORK.TEST was not replaced because this step was
      stopped."
   and the SAME example's following `proc print data=test` reports
     "NOTE: No variables in data set WORK.TEST."
   rather than "does not exist" — so the stopped step still left a member
   behind. That is the two-case rule this fixture pins.

   BUG-nofixturepinsrc: the failing step is the whole premise, so the exit code
   is pinned too (D-009 rc 1 — the user's SAS is what is wrong). Both program
   fixtures that legitimately exit non-zero now say so; the other 168 stay
   unpinned, which is why the marker is opt-in.
   expect-rc: 1

   Pre-fix (verified on a clean-rebuilt baseline binary): the compile-time gate
   at exec.zig:770 `return`s rather than erroring, so main.zig's `lib.put` still
   fired and TARGET.KEEPER — a live 3-observation member — came out with 0 rows
   and the failing step's schema. Asserting the ERROR alone passes with the bug;
   what has to be pinned is the SURVIVOR'S CONTENT, which is expected/keeper.csv.

   The failing step names TWO outputs on purpose: the extra output went through
   its own `lib.put` (up front, before the step even ran) and was equally
   destroyed — patching only the primary would have left the sibling broken. */

libname target "output";

/* A live 3-observation permanent member with its own schema. */
data target.keeper;
  input id k $ v;
  datalines;
1 aa 10
2 bb 20
3 cc 30
;
run;

/* FAILING STEP, LAST. `fresh` is a NEW name (primary output) and must still be
   created with 0 rows and its compile-time columns; `target.keeper` already
   exists (extra output) and must survive untouched. The gate is the undefined
   GOTO label (exec.zig:3916, compileProgram — one of the 8 GATED sites). */
data target.fresh target.keeper;
  length fa $3 fb 8;
  goto nowhere;
run;
