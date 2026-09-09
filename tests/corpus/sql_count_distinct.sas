data d;
  input g v;
  datalines;
1 10
1 10
1 .
1 20
2 5
2 .
;
run;
proc sql;
  create table t as select g, count(distinct v) as nd from d group by g;
quit;
data _null_;
  set t;
  put "g=" g " nd=" nd;
run;
