data d;
  input dt v;
  datalines;
21915 10
22281 20
21916 5
22282 100
;
run;

proc sql;
  create table t as
    select year(dt) as yr, count(*) as n, sum(v) as tot
    from d
    group by year(dt)
    order by yr;
quit;

data _null_;
  set t;
  put "yr=" yr " n=" n " tot=" tot;
run;
