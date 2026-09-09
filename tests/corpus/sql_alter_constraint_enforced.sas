/* BUG-sqlalteraddconstraint, half two: a constraint added by ALTER TABLE must be
   ENFORCED, not merely parsed. opensas genuinely enforces integrity constraints
   (BUG-sqlconstraints: per-row on INSERT/UPDATE via violatesConstraint), so ALTER
   must reach the SAME state CREATE TABLE reaches — no more, and no less.

   No less matters as much as no more: routing the clause away from the column
   path fixes the phantom column, but if the parsed constraint were then dropped
   on the floor, sql_alter_constraint.sas would go green while the constraint
   silently did nothing — a D-002 no-op, the failure class this repo ranks worst.

   ONE erroring step, and it is LAST on purpose: a step ERROR trips syntax-check
   mode (BUG-errhalt) and every later step is SKIPPED, so a fixture with several
   failing steps silently pins only its first one. The PROC PRINT above the error
   runs while the table is still clean and shows the constraint DISCRIMINATES —
   x=7 was accepted — rather than blanket-rejecting every insert, which is the
   way a broken enforcement path could still produce the required ERROR below.
   Per-kind enforcement (PK / UNIQUE / NOT NULL / FK) is shared code already
   pinned by sql_constraints.sas; what is new here is only where the constraint
   came from, so one kind proves the wiring.

   expect-rc: 1 */

data m1; x = 1; run;

proc sql;
  alter table m1 add constraint c1 check (x > 0);
  insert into m1 values(7);
quit;

proc print data=m1; run;

/* REQUIRED ERROR: the ALTER-added CHECK rejects a violating row. */
proc sql; insert into m1 values(-5); quit;
