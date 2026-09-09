data d;
  input x;
  datalines;
10
20
;
run;

proc sql;
  create table t as
    select x, x * 2 as dbl, calculated dbl + 1 as inc
    from d;
quit;

data _null_;
  set t;
  put "x=" x " dbl=" dbl " inc=" inc;
run;
