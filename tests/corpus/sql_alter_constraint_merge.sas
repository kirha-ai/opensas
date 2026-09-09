/* BUG-sqlalteraddconstraint, half two (b): an ALTER-added constraint must MERGE
   with the table's CREATE-time constraints, not SHADOW them.

   `constraintsOf` returns only the NEWEST registry entry for a Dataset, so
   runAlter has to re-register `old ++ new` as one list. Drop the `old` half and
   every constraint declared at CREATE TABLE silently stops being enforced the
   moment anyone ALTERs the table — a table that quietly loses its integrity
   constraints is worse than one that never had them, because the DDL says it
   does. That block predates this fix, but a table-level ADD CONSTRAINT is a new
   way to reach it, so the direction with the regression risk is pinned here.

   The error below is c1, declared at CREATE — it must STILL fire after the ALTER
   added c2. (c2 firing is the same mechanism pinned by
   sql_alter_constraint_enforced.sas.) One erroring step, last, per BUG-errhalt.

   expect-rc: 1 */

proc sql;
  create table n1 (a num, b num, constraint c1 check (a > 0));
  alter table n1 add constraint c2 check (b > 0);
  insert into n1 values(5, 2);
quit;

/* both constraints are satisfied here, so the row is in */
proc print data=n1; run;

/* REQUIRED ERROR: a violates the CREATE-time c1, which the ALTER must not have
   discarded when it registered c2. */
proc sql; insert into n1 values(-1, 5); quit;
