data have;
  input x;
  datalines;
5
12
3
20
;
run;

proc sql;
  create table t as
    select x from have where x > 10 order by x desc;
quit;

data _null_;
  set t;
  put "x=" x;
run;
