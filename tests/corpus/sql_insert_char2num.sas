/* BUG-sqltypeconsistency: INSERT/UPDATE of a char value into a NUMERIC column
   converts the SAS way (implicit w. informat) — no ERROR, never the raw text
   in a num cell: '12.5' -> 12.5 and '3.25' -> 3.25 with the "converted" NOTE;
   'abc' -> missing after the converted + "Invalid numeric data" NOTE pair.
   The NOTEs go to stderr; stdout shows the converted/missing values. */
proc sql;
  create table t (a num, b char(8));
  insert into t values ('12.5', 'x');
  insert into t values ('abc', 'y');
  insert into t values (7, 'z');
  select * from t;
  update t set a = '3.25' where b = 'z';
  select * from t;
quit;
