proc sql;
  create table t (id num, name char(10), score num);
  insert into t values (1, 'Ann', 10) values (2, 'Bob', 20);
  insert into t (id, name) values (3, 'Cy');
  update t set score = score + 5 where id = 1;
  delete from t where name = 'Bob';
quit;

data _null_;
  set t;
  put "id=" id " name=" name " score=" score;
run;
