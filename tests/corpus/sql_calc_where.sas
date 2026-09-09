data d;
  input x;
  datalines;
10
20
30
;
run;

proc sql;
  create table t as
    select x, x * 2 as dbl
    from d
    where calculated dbl > 25;
quit;

data _null_;
  set t;
  put "x=" x " dbl=" dbl;
run;
