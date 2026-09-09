/* BUG-sqlalteraddconstraint: ALTER TABLE's ADD clause implemented ADD COLUMN
   only, so a table-level integrity constraint was read as a COLUMN DEFINITION.
   `constraint`, `primary`, `unique`, `check` and `foreign` all lex as plain
   `.name`, so `alter table m add constraint c1 check (x > 0)` added a column
   literally named `constraint` — a silently corrupted schema at exit 0, with no
   diagnostic of any kind. All five spellings did it.

   THIS FIXTURE PINS THE SCHEMA, not the absence of an error: the bug never
   produced a message, so asserting only stdout/diagnostics is exactly how it
   survived. Each PROC CONTENTS below must show the table's ORIGINAL columns and
   nothing else — a phantom `constraint`/`primary`/`unique`/`check`/`foreign`
   column reappears here as an extra Variables line.

   Enforcement of these constraints is pinned separately in
   sql_alter_constraint_enforced.sas (rc 1) and the DROP CONSTRAINT / MODIFY gaps
   in sql_alter_constraint_gap.sas (rc 2) — parse-and-discard would be a D-002
   silent no-op and would still pass this file alone.
   expect-rc: 0 */

data p; y = 1; output; run;

/* 1. named table-level CHECK — the exact form in the ticket */
data m1; x = 1; run;
proc sql; alter table m1 add constraint c1 check (x > 0); quit;
proc contents data=m1; run;

/* 2. unnamed PRIMARY KEY */
data m2; x = 1; run;
proc sql; alter table m2 add primary key (x); quit;
proc contents data=m2; run;

/* 3. unnamed UNIQUE */
data m3; x = 1; run;
proc sql; alter table m3 add unique (x); quit;
proc contents data=m3; run;

/* 4. unnamed CHECK */
data m4; x = 1; run;
proc sql; alter table m4 add check (x > 0); quit;
proc contents data=m4; run;

/* 5. FOREIGN KEY … REFERENCES */
data m5; x = 1; run;
proc sql; alter table m5 add foreign key (x) references p(y); quit;
proc contents data=m5; run;

/* 6. multi-column PRIMARY KEY: the comma is INSIDE the parens and must NOT
      split the clause into two ALTER items (the old scan was not depth-aware) */
data m6; x = 1; y = 2; run;
proc sql; alter table m6 add primary key (x, y); quit;
proc contents data=m6; run;

/* 7. a column and a constraint in ONE comma-separated ALTER: y is a real new
      column, the constraint is not */
data m7; x = 1; run;
proc sql; alter table m7 add y num, constraint c1 check (x > 0); quit;
proc contents data=m7; run;

/* 8. CONTROLS — the plain ADD/DROP column paths must keep working unchanged */
data m8; x = 1; y = 9; run;
proc sql;
  alter table m8 add z num, w char(4);
  alter table m8 drop y;
quit;
proc contents data=m8; run;

/* 9. a row that SATISFIES an ALTER-added constraint still inserts cleanly */
data m9; x = 1; run;
proc sql;
  alter table m9 add constraint c1 check (x > 0);
  insert into m9 values(7);
quit;
proc print data=m9; run;
