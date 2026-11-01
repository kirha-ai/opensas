/* BUG-sqlbareconstraintaccept: PROC SQL used to ACCEPT an UNNAMED table-level
   integrity constraint in CREATE TABLE and silently enforce it, so
     proc sql; create table pk (id int, primary key(id)); select * from pk; quit;
   exited 0 and printed `id`. Real SAS 9.4 REJECTS it — the `constraint <name>`
   prefix is MANDATORY on a table-level clause (SQL Procedure User's Guide ch.4
   p.143 spells one `constraint prim_key primary key(state)`).
   Oracle, real SAS 9.4, 2026-11-01 (/tmp probes p1/p5/p8/p10/p12/p18): each of
   `primary key(id)` / `check (…)` / `unique(k)` / `distinct(k)` /
   `foreign key(…) references …` written WITHOUT a name logs
     ERROR 22-322: Syntax error, expecting one of the following: CHAR, CHARACTER,
                   DATE, DEC, DECIMAL, DOUBLE, FLOAT, INT, INTEGER, NUM, NUMERIC,
                   REAL, SMALLINT, VARCHAR.
     ERROR 76-322: Syntax error, statement will be ignored.
   the table is NOT created, and PROC SQL switches to NOEXEC for the rest of the
   step. SAS reaches that error because it parses EVERY non-`constraint`-prefixed
   item of the body as a COLUMN DEFINITION, and `primary` then has no data type —
   which is also why `create table t (primary num, id num)` is a legal table with
   a column called `primary` (oracle p9/p13), and why a plain typeless column
   (`create table t (id);`, oracle p17) draws the SAME 22-322. opensas mirrors
   that single rule.
   SAS exits 2 by its own convention; opensas 1 — a wrong user program, D-009.

   Layout: the POSITIVE control runs first in its own step so its listing is on
   stdout before the rejection halts anything (a fixture that only pinned the
   empty-output case would pass just as well if CREATE TABLE stopped working).
   The ERROR text itself is pinned by the BUG-sqlbareconstraintaccept test block
   in src/sql.zig, which reads the CAPTURED diagnostics reporter.
   expect-rc: 1 */

/* ACCEPTED: the named table-level form, and the column-level suffixes SAS allows
   unnamed (`not null` p3, `unique` p4, `primary key` p7, `check (…)` p6). */
proc sql;
  create table ok (id num, nm char(4), constraint ok_pk primary key(id));
  insert into ok values(2, 'two');
  insert into ok values(1, 'one');
  select * from ok order by id;

  create table colok (a num not null, b num unique, c num primary key, d num check (d >= 0));
  insert into colok values(1, 2, 3, 4);
  select * from colok;
quit;

/* REJECTED: the same constraint with no name. Fails LOUD, rc 1, table not made. */
proc sql;
  create table bare (id num, primary key(id));
  select * from bare;   /* never runs — the step is abandoned */
quit;
