data a; input id x; datalines;
1 10
2 20
3 30
;
run;
data b; input id; datalines;
2
3
;
run;
proc sql;
  create table semi as select id, x from a where exists (select 1 from b where b.id=a.id) order by id;
  create table anti as select id from a where not exists (select 1 from b where b.id=a.id) order by id;
quit;
data _null_; set semi; put "semi " id= x=; run;
data _null_; set anti; put "anti " id=; run;
