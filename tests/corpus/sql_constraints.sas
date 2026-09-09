/* BUG-sqlconstraints: CREATE TABLE integrity constraints used to parse as
   phantom `constraint`/`primary` COLUMNS and were never enforced — dup PK,
   failed CHECK, dup UNIQUE, NULL in NOT NULL all inserted silently.
   Now: the violating INSERT is an ERROR (stderr) and the row is rejected;
   a clean table has exactly its declared columns.
   expect-rc: 1 */
proc sql;
  create table pk (id num, primary key(id));
  insert into pk values(1);
  insert into pk values(1);  /* ERROR: duplicate primary key — row rejected */
  select * from pk;          /* one row, and NO phantom constraint column */

  create table nn (a num not null, b char);
  insert into nn values(5, 'x');
  insert into nn(a) values(6);   /* b stays blank — allowed */
  insert into nn(b) values('y'); /* ERROR: NOT NULL column a missing */
  select * from nn;

  create table ck (age num, check (age >= 18));
  insert into ck values(20);
  insert into ck values(7);   /* ERROR: CHECK failed */
  select * from ck;

  create table uq (k num unique);
  insert into uq values(1);
  insert into uq values(1);   /* ERROR: duplicate unique key */
  insert into uq values(.);   /* missings pass UNIQUE (SQL NULL semantics) */
  insert into uq values(.);
  select * from uq;
quit;
