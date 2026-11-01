/* BUG-sqlbarechecktypebypass: the CREATE TABLE missing-datatype guard that
   BUG-sqlbareconstraintaccept installed (D-028) counted type keywords ANYWHERE in
   a body item's token span — including inside a nested CHECK predicate. So a bare
   (unnamed) table constraint whose predicate merely MENTIONS a type keyword
   satisfied the guard and was accepted as a column:
     proc sql; create table t (x num, check(num >= 0)); select * from t; quit;
   exited 0 and printed the columns `x  check`. The `num` INSIDE the predicate is
   what defeated the guard.

   The rule, refined: the datatype must appear in the COLUMN-DEFINITION POSITION —
   directly after the column name, at parenthesis depth 0 of that item — never
   nested inside a predicate or any parenthesized sub-expression.

   Oracle, real SAS 9.4 on the dev box, 2026-11-01 (/tmp/dev1probe2). Every one of
   these logs the SAME diagnostics and does NOT create the table:
     ERROR 22-322: Syntax error, expecting one of the following: CHAR, CHARACTER,
                   DATE, DEC, DECIMAL, DOUBLE, FLOAT, INT, …
     ERROR 76-322: Syntax error, statement will be ignored.
     ERROR: File WORK.T<n>.DATA does not exist.
     q1  (x num, check(num >= 0))                  -- the ticket's repro
     q2  (x num, check(date is not null))          -- nested `not` as well
     q3  (x char(4), check(char(x) = 'a'))         -- type keyword as a call
     q4  (k num, unique(num))                      -- not only CHECK
     q10 (x num, primary key(num))                 -- nor only UNIQUE
     q6  (x num, constraint c1 check(x > 0), check(num >= 0))  -- named sibling: no
     q8  (x not null num)                          -- + ERROR 202-322
     q5  (k num, unique(k) num)                    -- + ERROR 200-322
   q5/q8 are why the rule is POSITIONAL and not merely depth-aware: there the type
   keyword IS at depth 0, just not where a datatype goes.
   ACCEPTED by the same oracle round, no ERROR, table created:
     q7  (x double precision)
     q9  (num num, constraint c1 check(num >= 0))  -- `num` is a fine column name,
         and a type keyword inside a NAMED clause's predicate is nobody's business
   SAS exits 2 by its own convention; opensas 1 — a wrong user program, D-009.

   Layout follows the lesson recorded in D-028: the POSITIVE control runs FIRST, in
   its own step, so the listing below proves CREATE TABLE still works — an empty
   golden cannot tell "the feature fired" from "the statement was refused". The
   ERROR text and the other seven rejected spellings are pinned by the
   BUG-sqlbarechecktypebypass half of the src/sql.zig test block, which reads the
   CAPTURED diagnostics reporter.
   expect-rc: 1 */

/* ACCEPTED (positive control): a type keyword inside a NAMED clause's predicate is
   not the column's datatype and does not make the clause illegal (oracle q9), a
   column may be NAMED `num` (q9), and `double precision` still parses (q7). */
proc sql;
  create table okc (num num, constraint okc_ck check(num >= 0));
  insert into okc values(7);
  select * from okc;   /* the named CHECK's enforcement is pinned in src/sql.zig */

  create table dbl (x double precision, nm char(3) check (nm <> ''));
  insert into dbl values(2.5, 'ab');
  select * from dbl;
quit;

/* REJECTED: the ticket's repro. The `num` in the predicate must NOT be mistaken
   for the item's datatype. Fails LOUD, rc 1, table not created. */
proc sql;
  create table t (x num, check(num >= 0));
  select * from t;   /* never runs — the step is abandoned */
quit;
