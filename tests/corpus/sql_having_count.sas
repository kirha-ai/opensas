data d;
  input g $ v;
  datalines;
a 1
a 2
a 3
b 5
c 7
c 8
;
run;

proc sql;
  create table t as
    select g, count(*) as n
    from d
    group by g
    having count(*) >= 2;
quit;

data _null_;
  set t;
  put "g=" g " n=" n;
run;
