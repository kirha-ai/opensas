data a; input x; datalines;
1
2
3
;
run;
data b; input x; datalines;
2
3
4
;
run;
proc sql;
  create table t (id num, nm char(8));
  insert into t values(1, "one");
  insert into t values(2, "two");
  select id, nm from t;
  select x from a intersect select x from b;
  select x from a except select x from b;
quit;
