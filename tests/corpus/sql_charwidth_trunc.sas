/* GAP-sqldatatypewidth: CREATE TABLE's char(n)/varchar(n) width was parsed but
   NOT enforced — char(3) stored 'abcdef' whole and CONTENTS showed the widest
   value, not 3. The declared width now truncates on INSERT/UPDATE (the SAS
   behavior for a too-long char value); exact- and under-width values store
   as-is (dynamic char storage, no blank-pad); a numeric (p,s) is precision/
   scale metadata — SAS stores numerics as doubles, so 123456 in a num(5)
   column keeps its value and CONTENTS shows Len 8. */
proc sql;
  create table t (c char(3), v varchar(4), n num(5));
  insert into t values('abcdef', 'wxyz12', 123456);
  insert into t values('ab', 'xy', 42);
  insert into t values('xyz', 'abcd', 7);
  update t set c = 'toolong' where n = 42;
  select * from t;
quit;
proc contents data=t; run;
