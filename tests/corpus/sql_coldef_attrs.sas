/* audit-tick: col_def / column_attr — CREATE TABLE with an explicit column
   list: char/varchar -> char storage, num -> numeric; NOT NULL is enforced,
   FORMAT= renders and LABEL= shows in CONTENTS. */
proc sql;
  create table t (a char(5) not null, b num format=mmddyy10. label="B label", c varchar(20));
  insert into t values ('x', 21929, 'y');
  select * from t;
quit;
proc contents data=t; run;
