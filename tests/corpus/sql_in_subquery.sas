data a;
  input id;
  datalines;
1
2
3
4
;
run;

data b;
  input id;
  datalines;
2
4
;
run;

proc sql;
  create table t as select id from a where id in (select id from b);
quit;

data _null_;
  set t;
  put "id=" id;
run;
