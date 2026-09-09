/* BUG-sqlalteraddconstraint, half three: the ALTER clauses we do NOT implement
   must stay loud and must be classed as GAPS, not user errors.

   DROP CONSTRAINT is valid SAS that opensas cannot do: a parsed Constraint
   carries no NAME (CREATE TABLE reads `constraint <name>` as metadata and skips
   it), so there is nothing to look a named constraint up by. That is a gap →
   rc 2 per D-009/D-009b(i), which it already returned — but it returned it
   through "ALTER TABLE DROP — column not found", because `constraint` fell into
   the DROP-COLUMN loop and missed. The rc was right for the wrong reason and the
   message sent the reader hunting a column that was never the subject.

   MODIFY is likewise unimplemented and unchanged here; it is pinned so the
   ADD-constraint work above cannot quietly turn it into something else.

   The schema lines matter as much as the messages: each table must be untouched
   afterwards — a failed DROP must not have half-removed anything.
   expect-rc: 2 */

/* DROP CONSTRAINT by name */
proc sql; create table n1 (a num, constraint c1 check (a > 0)); quit;
proc sql; alter table n1 drop constraint c1; quit;
proc contents data=n1; run;

/* DROP PRIMARY KEY */
data m1; x = 1; run;
proc sql; alter table m1 drop primary key; quit;
proc contents data=m1; run;

/* DROP FOREIGN KEY */
data m2; x = 1; run;
proc sql; alter table m2 drop foreign key f1; quit;
proc contents data=m2; run;

/* MODIFY — unchanged, still a gap */
data m3; x = 1; run;
proc sql; alter table m3 modify x format=best8.; quit;
proc contents data=m3; run;

/* a genuinely missing COLUMN keeps its own message — the new constraint arm must
   not swallow the case it sits in front of */
data m4; x = 1; run;
proc sql; alter table m4 drop nosuchcol; quit;
proc contents data=m4; run;
