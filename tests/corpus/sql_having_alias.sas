data d;
  input g $ v;
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
    select g, sum(v) as tot
    from d
    group by g
    having tot > 15
    order by g;
quit;

data _null_;
  set t;
  put "g=" g " tot=" tot;
run;
