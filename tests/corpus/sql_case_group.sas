data d;
  input dept $ v;
  datalines;
a 10
a 20
b 5
b 5
c 100
;
run;

proc sql;
  create table t as
    select dept,
      case when sum(v) >= 30 then "big" else "small" end as sz,
      count(*) as n
    from d
    group by dept
    order by dept;
quit;

data _null_;
  set t;
  put "dept=" dept " sz=" sz " n=" n;
run;
