data d;
  input x;
  datalines;
5
25
15
;
run;

proc sql;
  create table t as
    select x from d
    order by case when x < 10 then 1 when x < 20 then 2 else 3 end;
quit;

data _null_;
  set t;
  put "x=" x;
run;
