proc sql;
  create table t (id num, grp char(1), v num);
  insert into t values (1, 'a', 10) values (2, 'a', 20) values (3, 'b', 30) values (4, 'b', 40);
  update t set v = v * 10 where grp = 'b' and v > 30;
  delete from t where grp = 'a' and v = 20;
quit;

data _null_;
  set t;
  put "id=" id " grp=" grp " v=" v;
run;
