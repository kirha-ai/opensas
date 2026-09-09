/* QA tick236 GREEN tripwire (regression guard, not a new feature).
   The BUG-sqlerrorswallow landing rewired interleaveStep's step-run error path
   to fail loud on an unreported non-OOM SQL error. Highest regression risk: it
   must stay SILENT on VALID SQL. This threads a full valid DDL/DML sequence —
   CREATE(col attrs) / INSERT(bare + col-list) / UPDATE SET / ALTER ADD / DROP
   TABLE — through that path, then re-uses the dropped name to prove DROP truly
   removed it, and ends with a SELECT. Every statement is legal, so stdout is
   exactly the listing below and exit 0. If the error-swallow gate ever
   false-positives on a valid step, or DROP stops removing, this goes red.
   Synthetic. qa-sql-ddl-seq. */
proc sql;
  create table t (amt num format=dollar8. label='Amount', nm char(4));
  insert into t values(100, 'aa');
  insert into t (amt, nm) values(200, 'bb');
  update t set amt=amt+1 where nm='aa';
  alter table t add flag num;
  drop table t;
  /* recreating the just-dropped name only works if DROP removed the old t */
  create table t (v num);
  insert into t values(7);
  select v from t;
quit;
